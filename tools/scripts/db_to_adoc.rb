#!/usr/bin/env ruby
# frozen_string_literal: true
require 'pg'
require 'fileutils'
require 'date'
require 'graphviz'
require 'zip'
require 'yaml'
require_relative '../lib/config_loader'
require_relative '../lib/llm_client'
require_relative '../lib/translation_utils'

# --- кэш переводов для избежания повторных вызовов LLM ---
TRANSLATION_CACHE = {}

# --- глобальные переменные для пакетного перевода ---
MISSING_FIELDS = []
BATCH_SIZE = 50  # Размер пакета для перевода

# =============================================================================
# ПАРСИНГ АРГУМЕНТОВ КОМАНДНОЙ СТРОКИ
# =============================================================================

require 'optparse'

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: db_to_adoc.rb [options]"

  opts.on("--host HOST", "Database host") do |host|
    options[:host] = host
  end

  opts.on("--port PORT", "Database port") do |port|
    options[:port] = port
  end

  opts.on("--db DATABASE", "Database name") do |db|
    options[:db] = db
  end

  opts.on("--user USER", "Database user") do |user|
    options[:user] = user
  end

  opts.on("--pass PASSWORD", "Database password") do |pass|
    options[:pass] = pass
  end

  opts.on("--out OUTPUT_DIR", "Output directory") do |out|
    options[:out] = out
  end

  opts.on("--images IMAGES_DIR", "Images directory") do |images|
    options[:images] = images
  end

  opts.on("--use-llm", "Enable LLM translation") do
    options[:use_llm] = true
  end

  opts.on("--component COMPONENT", "Component name") do |component|
    options[:component] = component
  end
end.parse!

# --- загрузка конфигурации ---
if options[:component]
  config = ConfigLoader.load_config_for_component(options[:component])
else
  config = ConfigLoader.load_config
end
translate_comments = config.dig('db', 'translate') || false

# --- инициализация LLM клиента ---
llm_client = nil
translation_utils = nil
ollama_config = config.dig('ollama') || {}

# Создаем translation_utils для работы со словарем
dictionary_path = config.dig('db', 'dictionary') || 'tools/dictionary/database_translations.yml'
translation_utils = TranslationUtils.new(dictionary_path)

if ollama_config['enabled'] && options[:use_llm]
  # Очищаем лог переводов только один раз в начале
  translation_utils.clear_log
  
  prompt_name = config.dig('db', 'prompt') || 'db_translate_attribute'
  llm_client = LLMClient.new(
    ollama_config['host'] || 'http://localhost:11434',
    ollama_config['model'] || 'gpt-oss:20b',
    'tools/prompts',
    prompt_name
  )
  puts "🤖 LLM клиент инициализирован для перевода атрибутов"
elsif ollama_config['enabled'] && !options[:use_llm]
  puts "⚠️  LLM включен в конфигурации, но флаг --use-llm не передан"
else
  puts "⚠️  LLM отключен в конфигурации"
end

puts "🔧 Конфигурация загружена:"
puts "   translate_comments: #{translate_comments}"
puts "   dictionary: #{dictionary_path}"
puts "   prompt: #{config.dig('db', 'prompt') || 'db_translate_attribute'}"
puts "   llm_enabled: #{ollama_config['enabled']}"

def russian_text?(text)
  # Простая проверка на русский текст
  text.match?(/[а-яё]/i)
end

def correct_language?(translation, translate_comments)
  # Проверяем, соответствует ли язык перевода настройке
  return false if translation.nil? || translation.empty?
  
  case translate_comments
  when "ru", true
    # Должен быть русский - проверяем наличие русских букв
    russian_text?(translation)
  when "en"
    # Должен быть английский - проверяем отсутствие русских букв
    !russian_text?(translation)
  else
    # Для других случаев считаем корректным
    true
  end
end

def collect_missing_field(name, translate_comments, translation_utils)
  # Собираем поля, которых нет в словаре
  key = name.downcase
  
  if translation_utils
    existing_translations = translation_utils.send(:load_existing_translations)
    
    # Если поля нет в словаре или язык не совпадает
    if !existing_translations.key?(key) || !correct_language?(existing_translations[key], translate_comments)
      MISSING_FIELDS << name unless MISSING_FIELDS.include?(name)
    end
  end
end

def process_batch_translation(llm_client, translation_utils, translate_comments)
  # Обрабатываем пакет переводов
  return if MISSING_FIELDS.empty?
  
  puts "🔄 Обрабатываем пакет из #{MISSING_FIELDS.length} полей..."
  
  # Разбиваем на пакеты
  batches = MISSING_FIELDS.each_slice(BATCH_SIZE).to_a
  
  batches.each_with_index do |batch, index|
    puts "📦 Пакет #{index + 1}/#{batches.length}: #{batch.length} полей"
    
    # Переводим пакет
    translations = llm_client.translate_batch(batch, translate_comments)
    
    # Сохраняем переводы
    translations.each do |field, translation|
      translation_utils.add_translation(field, translation)
      TRANSLATION_CACHE["#{field}_#{translate_comments}"] = translation
    end
  end
  
  # Очищаем список
  MISSING_FIELDS.clear
end

def translate_field(name, comment = nil, translate_comments = false, llm_client = nil, translation_utils = nil)
  # Если есть комментарий - НИКОГДА не переводим, используем как есть
  if comment && !comment.empty?
    return comment
  end
  
  # Проверяем кэш
  cache_key = "#{name}_#{translate_comments}"
  return TRANSLATION_CACHE[cache_key] if TRANSLATION_CACHE.key?(cache_key)
  
  # Если нет комментария - переводим в зависимости от настройки translate_comments
  key = name.downcase
  
  # При translate_comments = false - НЕ ТРОГАЕМ ВООБЩЕ, возвращаем как есть
  if translate_comments == false
    TRANSLATION_CACHE[cache_key] = name
    return name
  end
  
  # СНАЧАЛА проверяем словарь (для всех режимов перевода)
  if translation_utils
    existing_translations = translation_utils.send(:load_existing_translations)
    if existing_translations.key?(key)
      dictionary_translation = existing_translations[key]
      
      # Проверяем, соответствует ли язык перевода настройке
      if correct_language?(dictionary_translation, translate_comments)
        puts "📖 Перевод из словаря: '#{name}' → '#{dictionary_translation}'"
        TRANSLATION_CACHE[cache_key] = dictionary_translation
        return dictionary_translation
      else
        puts "⚠️ Перевод в словаре на другом языке (#{dictionary_translation}), добавляем в пакет"
        collect_missing_field(name, translate_comments, translation_utils)
      end
    else
      # Поля нет в словаре - добавляем в пакет
      collect_missing_field(name, translate_comments, translation_utils)
    end
  end
  
  # Если LLM недоступен - используем fallback
  unless llm_client
    fallback = name
      .gsub(/([a-z])([A-Z])/, '\1 \2')
      .tr('_', ' ')
    TRANSLATION_CACHE[cache_key] = fallback
    return fallback
  end
  
  # Возвращаем имя как есть - перевод будет обработан пакетным
  TRANSLATION_CACHE[cache_key] = name
  name
end

# ---------- настройки подключения ----------
# Используем аргументы командной строки или значения по умолчанию
DB_HOST = options[:host] || 'localhost'
DB_PORT = options[:port] || '5432'
DB_NAME = options[:db] || 'demo'
DB_USER = options[:user] || 'postgres'
DB_PASS = options[:pass] || 'postgres'

conn = PG.connect(
  host: DB_HOST,
  port: DB_PORT,
  dbname: DB_NAME,
  user: DB_USER,
  password: DB_PASS
)

# ---------- каталоги вывода ----------
# Используем настройку dst из конфигурации, подставляя имя компонента
if options[:component] && config.dig('db', 'dst')
  OUT_DIR = config['db']['dst'].gsub('{name}', options[:component])
else
  OUT_DIR = options[:out] || 'output'
end

# SVG изображения в отдельную директорию (переданную через --images или по умолчанию)
if options[:component] && config.dig('db', 'images_dir')
  IMAGES_DIR = config['db']['images_dir'].gsub('{name}', options[:component])
else
  IMAGES_DIR = options[:images] || File.join(File.dirname(OUT_DIR), 'images', 'bd-images')
end

FileUtils.mkdir_p(OUT_DIR)
FileUtils.mkdir_p(IMAGES_DIR)

# Очистка предыдущих артефактов
Dir.glob(File.join(OUT_DIR, '*.{adoc,puml,png,zip}')).each { |f| FileUtils.rm_f(f) }
Dir.glob(File.join(IMAGES_DIR, '*.svg')).each { |f| FileUtils.rm_f(f) }

puts "🚀 Генерация полной документации базы данных..."
puts "📁 Выходная папка: #{OUT_DIR}"

# =============================================================================
# 0. ПРЕДВАРИТЕЛЬНЫЙ СБОР ДАННЫХ И ПОЛЕЙ ДЛЯ ПЕРЕВОДА
# =============================================================================

puts "\n📋 Сбор данных и полей для перевода..."

# SQL: только таблицы (без представлений) с комментариями
sql = <<~SQL
  SELECT c.table_schema, c.table_name, c.column_name, c.data_type,
         CASE c.is_nullable WHEN 'NO' THEN 'Да' ELSE 'Нет' END AS notnull,
         COALESCE(pgd.description, '') AS comment
  FROM information_schema.columns c
  LEFT JOIN pg_class pgc ON pgc.relname = c.table_name
  LEFT JOIN pg_namespace pgn ON pgn.oid = pgc.relnamespace AND pgn.nspname = c.table_schema
  LEFT JOIN pg_description pgd ON pgd.objoid = pgc.oid AND pgd.objsubid = c.ordinal_position
  WHERE c.table_schema NOT IN ('pg_catalog', 'information_schema')
    AND c.table_name   NOT LIKE 'pg_%'
    AND c.table_name   NOT LIKE 'sql_%'
    AND pgc.relkind = 'r'  -- только таблицы (r = relation/table)
  ORDER BY c.table_schema, c.table_name, c.ordinal_position;
SQL

rows = conn.exec(sql).to_a
abort 'Запрос не вернул ни одной колонки!' if rows.empty?
puts "   Получено колонок: #{rows.size}"

# группируем данные: {schema => {table => [cols]}}
schemas = Hash.new { |h, k| h[k] = Hash.new { |t, n| t[n] = [] } }
rows.each { |r| schemas[r['table_schema']][r['table_name']] << r }

# Собираем поля для перевода (без генерации документации)
puts "   🔍 Сбор полей для перевода..."
schemas.each do |schema, tables|
  # получаем комментарии к таблицам
  table_comments = conn.exec(
    "SELECT t.table_name, COALESCE(pgd.description, '') AS comment FROM information_schema.tables t JOIN pg_class pgc ON pgc.relname = t.table_name JOIN pg_namespace pgn ON pgn.oid = pgc.relnamespace AND pgn.nspname = t.table_schema LEFT JOIN pg_description pgd ON pgd.objoid = pgc.oid AND pgd.objsubid = 0 WHERE t.table_schema = $1 AND pgc.relkind = 'r' ORDER BY t.table_name;",
    [schema]
  ).to_a
  
  # создаем хэш комментариев для быстрого поиска
  comments_hash = table_comments.map { |tc| [tc['table_name'], tc['comment']] }.to_h

  tables.each do |table, cols|
    # Собираем поля таблицы для перевода
    cols.each do |c|
      translate_field(c['column_name'], c['comment'], translate_comments, llm_client, translation_utils)
    end
    
    # Собираем названия таблиц для перевода
    table_comment = comments_hash[table] || ''
    translate_field(table, table_comment, translate_comments, llm_client, translation_utils)
  end
end

# Также собираем поля для логической документации
puts "   🔍 Сбор полей для логической документации..."

# выборка всех пользовательских схем
schemata = conn.exec(
  <<~SQL
    SELECT schema_name
    FROM information_schema.schemata
    WHERE schema_name NOT IN ('pg_catalog', 'information_schema')
      AND schema_name NOT LIKE 'pg_temp_%'
      AND schema_name NOT LIKE 'pg_toast%'
    ORDER BY schema_name;
  SQL
).to_a

schemata.each do |schema_row|
  schema = schema_row['schema_name']
  
  # выборка таблиц схемы
  tables = conn.exec(
    "SELECT t.table_name, COALESCE(pgd.description, '') AS comment FROM information_schema.tables t JOIN pg_class pgc ON pgc.relname = t.table_name JOIN pg_namespace pgn ON pgn.oid = pgc.relnamespace AND pgn.nspname = t.table_schema LEFT JOIN pg_description pgd ON pgd.objoid = pgc.oid AND pgd.objsubid = 0 WHERE t.table_schema = $1 AND pgc.relkind = 'r' ORDER BY t.table_name;",
    [schema]
  ).to_a

  next if tables.empty?

  tables.each do |table_row|
    table_name = table_row['table_name']
    table_comment = table_row['comment']
    translate_field(table_name, table_comment, translate_comments, llm_client, translation_utils)
  end
end

puts "   ✅ Собрано полей для перевода: #{MISSING_FIELDS.length}"

# =============================================================================
# 0.5. ПЕРЕВОД ЧЕРЕЗ LLM (ЕСЛИ НУЖНО)
# =============================================================================

# Обрабатываем переводы пакетным (только для полей, которые действительно используются)
if llm_client && !MISSING_FIELDS.empty?
  puts "\n🔄 Обрабатываем переводы через LLM..."
  process_batch_translation(llm_client, translation_utils, translate_comments)
end

# =============================================================================
# 1. ГЕНЕРАЦИЯ ТАБЛИЧНОЙ ДОКУМЕНТАЦИИ (ПОСЛЕ ПЕРЕВОДА)
# =============================================================================

puts "\n📊 Генерация табличной документации..."

# создаем табличную документацию
master_index_path = File.join(OUT_DIR, 'schemas_index.adoc')
master_index = +''

schemas.each do |schema, tables|
  agg_path = File.join(OUT_DIR, "#{schema}_tables.adoc")
  agg_body = +""

  # получаем комментарии к таблицам
  table_comments = conn.exec(
    "SELECT t.table_name, COALESCE(pgd.description, '') AS comment FROM information_schema.tables t JOIN pg_class pgc ON pgc.relname = t.table_name JOIN pg_namespace pgn ON pgn.oid = pgc.relnamespace AND pgn.nspname = t.table_schema LEFT JOIN pg_description pgd ON pgd.objoid = pgc.oid AND pgd.objsubid = 0 WHERE t.table_schema = $1 AND pgc.relkind = 'r' ORDER BY t.table_name;",
    [schema]
  ).to_a
  
  # создаем хэш комментариев для быстрого поиска
  comments_hash = table_comments.map { |tc| [tc['table_name'], tc['comment']] }.to_h

  tables.each do |table, cols|
    agg_body << <<~TABLE
      :num_t: {counter:table-number}

      Описание данных «#{table}» приведено в <<id_t_{num_t}, Таблице {num_t}>>.

      [#id_t_{num_t}]
      .Таблица {num_t}. Описание таблицы «#{table}»
      [cols="2, 2, 2, 4", options="header, breakable"]
      |===
      ^|Название ^|Тип данных ^|Обязательность ^|Описание
    TABLE

    cols.each do |c|
      desc = translate_field(c['column_name'], c['comment'], translate_comments, llm_client, translation_utils)
      agg_body << "|#{c['column_name']} |#{c['data_type']} |#{c['notnull']} |#{desc}\n"
    end

    agg_body << "|===\n\n"
  end

  File.write(agg_path, agg_body)

  master_index << <<~SCHEMA
    [%breakable]
    ==== Схема данных «#{schema}»

    Схема данных в виде ERD-диаграммы представлена на рисунке «erd_#{schema}.svg» в архиве «bd_images_#{Date.today.strftime('%Y-%m-%d')}.zip», являющемся приложением к данному документу.

    :num_t: {counter:table-number}
    Перечень таблиц данных схемы «#{schema}» приведен в <<id_t_{num_t}, Таблице {num_t}>>.

    [#id_t_{num_t}]
    .Таблица {num_t}. Перечень таблиц данных схемы «#{schema}»
    [cols="2, 4", options="header, breakable"]
    |===
    ^|Название ^|Описание
  SCHEMA
  
  tables.keys.each do |table|
    table_comment = comments_hash[table] || ''
    desc = translate_field(table, table_comment, translate_comments, llm_client, translation_utils)
    master_index << "|#{table} |#{desc}\n"
  end
  master_index << "|===\n\n"
  master_index << "include::#{schema}_tables.adoc[]\n\n"
end

File.write(master_index_path, master_index)
puts "   ✅ Табличная документация создана"

# =============================================================================
# 2. ГЕНЕРАЦИЯ ЛОГИЧЕСКОЙ ДОКУМЕНТАЦИИ
# =============================================================================

puts "\n🔗 Генерация логической документации..."

# создаем логическую документацию
logical_index_path = File.join(OUT_DIR, 'schemas_logical_index.adoc')
logical_index = +''

schemata.each do |schema_row|
  schema = schema_row['schema_name']
  
  # выборка таблиц схемы
  tables = conn.exec(
    "SELECT t.table_name, COALESCE(pgd.description, '') AS comment FROM information_schema.tables t JOIN pg_class pgc ON pgc.relname = t.table_name JOIN pg_namespace pgn ON pgn.oid = pgc.relnamespace AND pgn.nspname = t.table_schema LEFT JOIN pg_description pgd ON pgd.objoid = pgc.oid AND pgd.objsubid = 0 WHERE t.table_schema = $1 AND pgc.relkind = 'r' ORDER BY t.table_name;",
    [schema]
  ).to_a

  next if tables.empty?

  # выборка связей между таблицами
  relations = conn.exec(
    "SELECT tc.table_name AS source_table, kcu.column_name AS source_column, ccu.table_name AS target_table, ccu.column_name AS target_column FROM information_schema.table_constraints AS tc JOIN information_schema.key_column_usage AS kcu ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema JOIN information_schema.constraint_column_usage AS ccu ON ccu.constraint_name = tc.constraint_name AND ccu.table_schema = tc.table_schema WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_schema = $1 ORDER BY tc.table_name, kcu.column_name;",
    [schema]
  ).to_a

  # создаем файл логической документации для схемы
  logical_path = File.join(OUT_DIR, "#{schema}_logical.adoc")
  logical_body = +''

  # сущности
  logical_body << <<~ENTITIES
    :num_t: {counter:logical-number}

    Описание сущностей схемы «#{schema}» приведено в <<id_l_{num_t}, Таблице {num_t}>>.

    [#id_l_{num_t}]
    .Таблица {num_t}. Сущности схемы «#{schema}»
    [cols="2,4",options="header,breakable"]
    |===
    ^|Сущность ^|Описание
  ENTITIES

  tables.each do |table_row|
    table_name = table_row['table_name']
    table_comment = table_row['comment']
    desc = translate_field(table_name, table_comment, translate_comments, llm_client, translation_utils)
    logical_body << "|#{table_name} |#{desc}\n"
  end
  logical_body << "|===\n\n"

  # связи
  if relations.any?
    logical_body << <<~RELATIONS
      :num_t: {counter:logical-number}

      Описание связей между сущностями схемы «#{schema}» приведено в <<id_l_{num_t}, Таблице {num_t}>>.

      [#id_l_{num_t}]
      .Таблица {num_t}. Связи между сущностями схемы «#{schema}»
      [cols="2,4,2,4",options="header,breakable"]
      |===
      ^|Источник ^|Ключ ^|Приёмник ^|Ключ
    RELATIONS

    relations.each do |rel|
      logical_body << "|#{rel['source_table']} |#{rel['source_column']} |#{rel['target_table']} |#{rel['target_column']}\n"
    end
    logical_body << "|===\n\n"
  end

  File.write(logical_path, logical_body)

  # добавляем в общий индекс с описанием и ссылкой на PlantUML диаграмму
  logical_index << <<~SCHEMA
    [%breakable]
    ==== Логическая схема «#{schema}»

    Логическая схема представлена на рисунке «logical_#{schema}.svg» в архиве «bd_images_#{Date.today.strftime('%Y-%m-%d')}.zip», являющемся приложением к данному документу.

    include::#{schema}_logical.adoc[]

  SCHEMA
end

File.write(logical_index_path, logical_index)
puts "   ✅ Логическая документация создана"

# =============================================================================
# 3. ГЕНЕРАЦИЯ PLANTUML ДИАГРАММ
# =============================================================================

puts "\n🎨 Генерация PlantUML диаграмм..."

schemata.each do |schema_row|
  schema = schema_row['schema_name']
  
  # выборка таблиц схемы
  tables = conn.exec(
    "SELECT t.table_name, COALESCE(pgd.description, '') AS comment FROM information_schema.tables t JOIN pg_class pgc ON pgc.relname = t.table_name JOIN pg_namespace pgn ON pgn.oid = pgc.relnamespace AND pgn.nspname = t.table_schema LEFT JOIN pg_description pgd ON pgd.objoid = pgc.oid AND pgd.objsubid = 0 WHERE t.table_schema = $1 AND pgc.relkind = 'r' ORDER BY t.table_name;",
    [schema]
  ).to_a

  next if tables.empty?

  # выборка связей между таблицами (упрощенная версия)
  fks = conn.exec(
    "SELECT tc.table_name AS src, MIN(kcu.column_name) AS src_col, ccu.table_name AS dst, MIN(ccu.column_name) AS dst_col FROM information_schema.table_constraints tc JOIN information_schema.key_column_usage kcu ON kcu.constraint_name = tc.constraint_name AND kcu.constraint_schema = tc.table_schema JOIN information_schema.constraint_column_usage ccu ON ccu.constraint_name = tc.constraint_name AND ccu.constraint_schema = tc.table_schema WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_schema = $1 GROUP BY tc.table_name, ccu.table_name;",
    [schema]
  ).to_a

  # выводим только классы, участвующие в FK
  relevant_tables = (fks.flat_map { |fk| [fk['src'], fk['dst']] } & tables.map { |t| t['table_name'] }).uniq
  
  # если в схеме нет таблиц, участвующих в FK-связях, пропускаем генерацию
  if relevant_tables.empty?
    puts "   ⚠️  Для схемы '#{schema}' логические связи отсутствуют"
    next
  end

  # генерируем PlantUML
  puml_lines = []
  puml_lines << "@startuml"
  puml_lines << "hide stereotype"
  puml_lines << "hide circle"
  puml_lines << "skinparam class {"
  puml_lines << "  BackgroundColor White"
  puml_lines << "  BorderColor Black"
  puml_lines << "  ArrowColor Black"
  puml_lines << "  FontColor Black"
  puml_lines << "}"
  puml_lines << "skinparam classAttributeIconSize 0"
  puml_lines << "left to right direction"

  relevant_tables.each do |tbl|
    # В PlantUML используем оригинальные английские названия таблиц
    puml_lines << "class #{tbl}"
  end

  fks.each do |fk|
    puml_lines << "#{fk['src']} ||--o{ #{fk['dst']} : \"#{fk['src_col']} → #{fk['dst_col']}\""
  end

  puml_lines << "@enduml"

  # сохраняем PlantUML файл
  puml_path = File.join(OUT_DIR, "logical_#{schema}.puml")
  File.write(puml_path, puml_lines.join("\n"))
  
  puts "   ✅ PlantUML диаграмма для схемы '#{schema}' создана"
end

# =============================================================================
# 3.5. ГЕНЕРАЦИЯ ЛОГИЧЕСКИХ PNG ДИАГРАММ
# =============================================================================

puts "\n🎨 Генерация логических PNG диаграмм..."

schemata.each do |schema_row|
  schema = schema_row['schema_name']
  
  # выборка таблиц схемы
  tables = conn.exec(
    "SELECT t.table_name, COALESCE(pgd.description, '') AS comment FROM information_schema.tables t JOIN pg_class pgc ON pgc.relname = t.table_name JOIN pg_namespace pgn ON pgn.oid = pgc.relnamespace AND pgn.nspname = t.table_schema LEFT JOIN pg_description pgd ON pgd.objoid = pgc.oid AND pgd.objsubid = 0 WHERE t.table_schema = $1 AND pgc.relkind = 'r' ORDER BY t.table_name;",
    [schema]
  ).to_a

  next if tables.empty?

  # выборка связей между таблицами (упрощенная версия)
  fks = conn.exec(
    "SELECT tc.table_name AS src, MIN(kcu.column_name) AS src_col, ccu.table_name AS dst, MIN(ccu.column_name) AS dst_col FROM information_schema.table_constraints tc JOIN information_schema.key_column_usage kcu ON kcu.constraint_name = tc.constraint_name AND kcu.constraint_schema = tc.table_schema JOIN information_schema.constraint_column_usage ccu ON ccu.constraint_name = tc.constraint_name AND ccu.constraint_schema = tc.table_schema WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_schema = $1 GROUP BY tc.table_name, ccu.table_name;",
    [schema]
  ).to_a

  # выводим только классы, участвующие в FK
  relevant_tables = (fks.flat_map { |fk| [fk['src'], fk['dst']] } & tables.map { |t| t['table_name'] }).uniq
  
  # если в схеме нет таблиц, участвующих в FK-связях, пропускаем генерацию
  if relevant_tables.empty?
    next
  end

  # генерируем PlantUML для SVG
  puml_lines = []
  puml_lines << "@startuml"
  puml_lines << "hide stereotype"
  puml_lines << "hide circle"
  puml_lines << "skinparam class {"
  puml_lines << "  BackgroundColor White"
  puml_lines << "  BorderColor Black"
  puml_lines << "  ArrowColor Black"
  puml_lines << "  FontColor Black"
  puml_lines << "}"
  puml_lines << "skinparam classAttributeIconSize 0"
  puml_lines << "left to right direction"

  relevant_tables.each do |tbl|
    # В PlantUML используем оригинальные английские названия таблиц
    puml_lines << "class #{tbl}"
  end

  fks.each do |fk|
    puml_lines << "#{fk['src']} ||--o{ #{fk['dst']} : \"#{fk['src_col']} → #{fk['dst_col']}\""
  end

  puml_lines << "@enduml"

  # генерируем PNG из существующего PlantUML файла
  puml_path = File.join(OUT_DIR, "logical_#{schema}.puml")
  system("plantuml -tsvg #{puml_path}")
  
  # перемещаем SVG файл в папку images
  source_svg = File.join(OUT_DIR, "logical_#{schema}.svg")
  target_svg = File.join(IMAGES_DIR, "logical_#{schema}.svg")
  if File.exist?(source_svg)
    FileUtils.mv(source_svg, target_svg)
  end
  
  puts "   ✅ Логическая SVG диаграмма для схемы '#{schema}' создана"
end

# =============================================================================
# 4. ГЕНЕРАЦИЯ ERD ДИАГРАММ
# =============================================================================

puts "\n📈 Генерация ERD диаграмм..."

schemata.each do |schema_row|
  schema = schema_row['schema_name']
  
  # выборка таблиц и их колонок
  tables_data = conn.exec(
    "SELECT t.table_name, c.column_name, c.data_type, c.is_nullable, CASE WHEN pk.column_name IS NOT NULL THEN 'YES' ELSE 'NO' END AS is_primary_key FROM information_schema.tables t JOIN pg_class pgc ON pgc.relname = t.table_name JOIN pg_namespace pgn ON pgn.oid = pgc.relnamespace AND pgn.nspname = t.table_schema LEFT JOIN information_schema.columns c ON t.table_name = c.table_name AND t.table_schema = c.table_schema LEFT JOIN (SELECT ku.table_name, ku.column_name FROM information_schema.table_constraints tc JOIN information_schema.key_column_usage ku ON tc.constraint_name = ku.constraint_name WHERE tc.constraint_type = 'PRIMARY KEY' AND tc.table_schema = $1) pk ON t.table_name = pk.table_name AND c.column_name = pk.column_name WHERE t.table_schema = $1 AND pgc.relkind = 'r' ORDER BY t.table_name, c.ordinal_position;",
    [schema]
  ).to_a
  
  next if tables_data.empty?

  # группируем данные по таблицам
  tables_hash = Hash.new { |h, k| h[k] = [] }
  tables_data.each { |row| tables_hash[row['table_name']] << row }

  # выборка связей
  relations = conn.exec(
    "SELECT tc.table_name AS source_table, kcu.column_name AS source_column, ccu.table_name AS target_table, ccu.column_name AS target_column FROM information_schema.table_constraints AS tc JOIN information_schema.key_column_usage AS kcu ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema JOIN information_schema.constraint_column_usage AS ccu ON ccu.constraint_name = tc.constraint_name AND ccu.table_schema = tc.table_schema WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_schema = $1 ORDER BY tc.table_name, kcu.column_name;",
    [schema]
  ).to_a

  # создаем Graphviz диаграмму
  g = GraphViz.new("G", type: :digraph, rankdir: "TB")
  g[:rankdir] = "TB"
  g[:fontname] = "Arial"
  g[:fontsize] = "10"

  # создаем узлы для таблиц
  table_nodes = {}
  tables_hash.each do |table_name, columns|
    node = g.add_node(table_name, shape: :record, style: :filled, fillcolor: :lightblue)
    table_nodes[table_name] = node
    
    # формируем label с колонками
    label_parts = ["#{table_name}"]
    columns.each do |col|
      pk_marker = col['is_primary_key'] == 'YES' ? ' *' : ''
      nullable_marker = col['is_nullable'] == 'NO' ? ' NOT NULL' : ''
      label_parts << "#{col['column_name']}#{pk_marker}#{nullable_marker}"
    end
    node[:label] = label_parts.join("|")
  end

  # создаем связи
  relations.each do |rel|
    source_node = table_nodes[rel['source_table']]
    target_node = table_nodes[rel['target_table']]
    
    if source_node && target_node
      g.add_edge(source_node, target_node, 
                label: "#{rel['source_column']} → #{rel['target_column']}",
                fontsize: "8")
    end
  end

  # сохраняем PNG в папку images
  svg_path = File.join(IMAGES_DIR, "erd_#{schema}.svg")
  g.output(svg: svg_path)
  
  # создаем ERD диаграмму в формате PlantUML
  erd_puml_lines = []
  erd_puml_lines << "@startuml"
  erd_puml_lines << "hide stereotype"
  erd_puml_lines << "hide circle"
  erd_puml_lines << "skinparam class {"
  erd_puml_lines << "  BackgroundColor LightBlue"
  erd_puml_lines << "  BorderColor Black"
  erd_puml_lines << "  ArrowColor Black"
  erd_puml_lines << "  FontColor Black"
  erd_puml_lines << "}"
  erd_puml_lines << "skinparam classAttributeIconSize 0"
  erd_puml_lines << "left to right direction"
  
  # добавляем все таблицы с их колонками
  tables_hash.each do |table_name, columns|
    erd_puml_lines << "class #{table_name} {"
    columns.each do |col|
      pk_marker = col['is_primary_key'] == 'YES' ? ' **' : ''
      nullable_marker = col['is_nullable'] == 'NO' ? ' NOT NULL' : ''
      erd_puml_lines << "  #{col['column_name']} : #{col['data_type']}#{pk_marker}#{nullable_marker}"
    end
    erd_puml_lines << "}"
  end
  
  # добавляем связи
  relations.each do |rel|
    erd_puml_lines << "#{rel['source_table']} ||--o{ #{rel['target_table']} : \"#{rel['source_column']} → #{rel['target_column']}\""
  end
  
  erd_puml_lines << "@enduml"
  
  # сохраняем ERD PlantUML файл
  erd_puml_path = File.join(OUT_DIR, "erd_#{schema}.puml")
  File.write(erd_puml_path, erd_puml_lines.join("\n"))
  
  puts "   ✅ ERD диаграмма для схемы '#{schema}' создана (SVG + PUML)"
end

# =============================================================================
# 5. СОЗДАНИЕ АРХИВА ИЗОБРАЖЕНИЙ (только SVG)
# =============================================================================

puts "\n🖼️  Создание архива изображений..."

# Создаем имя архива изображений
images_archive_name = "bd_images_#{Date.today.strftime('%Y-%m-%d')}.zip"
images_archive_path = File.join(OUT_DIR, images_archive_name)

# Создаем ZIP архив изображений (только PNG из папки images)
Zip::File.open(images_archive_path, create: true) do |zipfile|
  puts "   📁 Обработка папки: #{IMAGES_DIR}"
  
  # Ищем все PNG файлы в папке images
  svg_files = Dir.glob(File.join(IMAGES_DIR, '*.svg'))
  
  svg_files.each do |svg_file|
    filename = File.basename(svg_file)
    
    # Добавляем файл в корень архива (без папки images/)
    zipfile.add(filename, svg_file)
    puts "     ✅ Добавлен: #{filename}"
  end
  
  # PUML файлы НЕ добавляем в архив - только SVG
end

puts "   ✅ Архив изображений создан: #{images_archive_name}"

# =============================================================================
# ЗАВЕРШЕНИЕ
# =============================================================================

puts "\n🎉 Документация успешно сгенерирована!"
puts "📁 Папка: #{OUT_DIR}"
puts "📄 Файлы:"
puts "   - schemas_index.adoc (главный индекс)"
puts "   - schemas_logical_index.adoc (логический индекс)"
puts "   - *_tables.adoc (табличная документация)"
puts "   - *_logical.adoc (логическая документация)"
puts "   - images/erd_*.svg (ERD диаграммы)"
puts "   - images/logical_*.svg (логические диаграммы)"
puts "   - logical_*.puml (PlantUML диаграммы)"
puts "   - #{images_archive_name} (архив только SVG изображений)"

puts "\n✅ Генерация документации БД завершена!"

conn.close