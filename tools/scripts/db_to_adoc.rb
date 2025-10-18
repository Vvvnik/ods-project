#!/usr/bin/env ruby
# frozen_string_literal: true
require 'pg'
require 'fileutils'
require 'date'
require 'graphviz'
require 'zip'
require 'yaml'
require_relative 'translations_one'
# --- словарь переводов ---
TRANSLATIONS = EXTRA_TRANSLATIONS

def translate_field(name)
  key = name.downcase
  return TRANSLATIONS[key] if TRANSLATIONS.key?(key)

  # fallback: camelCase / snake_case → читаемая строка
  name
    .gsub(/([a-z])([A-Z])/, '\1 \2')
    .tr('_', ' ')
    .capitalize
end

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
end.parse!

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
OUT_DIR = options[:out] || 'output'
# SVG изображения в отдельную директорию (переданную через --images или по умолчанию)
IMAGES_DIR = options[:images] || File.join(File.dirname(OUT_DIR), 'images', 'bd-images')
FileUtils.mkdir_p(OUT_DIR)
FileUtils.mkdir_p(IMAGES_DIR)

# Очистка предыдущих артефактов
Dir.glob(File.join(OUT_DIR, '*.{adoc,puml,png,zip}')).each { |f| FileUtils.rm_f(f) }
Dir.glob(File.join(IMAGES_DIR, '*.svg')).each { |f| FileUtils.rm_f(f) }

puts "🚀 Генерация полной документации базы данных..."
puts "📁 Выходная папка: #{OUT_DIR}"

# =============================================================================
# 1. ГЕНЕРАЦИЯ ТАБЛИЧНОЙ ДОКУМЕНТАЦИИ
# =============================================================================

puts "\n📊 Генерация табличной документации..."

# SQL: все пользовательские схемы
sql = <<~SQL
  SELECT table_schema, table_name, column_name, data_type,
         CASE is_nullable WHEN 'NO' THEN 'Да' ELSE 'Нет' END AS notnull
  FROM information_schema.columns
  WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
    AND table_name   NOT LIKE 'pg_%'
    AND table_name   NOT LIKE 'sql_%'
  ORDER BY table_schema, table_name, ordinal_position;
SQL

rows = conn.exec(sql).to_a
abort 'Запрос не вернул ни одной колонки!' if rows.empty?
puts "   Получено колонок: #{rows.size}"

# группируем данные: {schema => {table => [cols]}}
schemas = Hash.new { |h, k| h[k] = Hash.new { |t, n| t[n] = [] } }
rows.each { |r| schemas[r['table_schema']][r['table_name']] << r }

# создаем табличную документацию
master_index_path = File.join(OUT_DIR, 'schemas_index.adoc')
master_index = +''

schemas.each do |schema, tables|
  agg_path = File.join(OUT_DIR, "#{schema}_tables.adoc")
  agg_body = +""

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
      desc = translate_field(c['column_name'])
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
    desc = translate_field(table)
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

abort 'Запрос не вернул ни одной схемы!' if schemata.empty?

# создаем логическую документацию
logical_index_path = File.join(OUT_DIR, 'schemas_logical_index.adoc')
logical_index = +''

schemata.each do |schema_row|
  schema = schema_row['schema_name']
  
  # выборка таблиц схемы
  tables = conn.exec(
    "SELECT table_name FROM information_schema.tables WHERE table_schema = $1 ORDER BY table_name;",
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
    desc = translate_field(table_name)
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
    "SELECT table_name FROM information_schema.tables WHERE table_schema = $1 ORDER BY table_name;",
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
    display = translate_field(tbl)
    if display == tbl
      puml_lines << "class #{tbl}"
    else
      puml_lines << "class \"#{display}\" as #{tbl}"
    end
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
    "SELECT table_name FROM information_schema.tables WHERE table_schema = $1 ORDER BY table_name;",
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
    display = translate_field(tbl)
    if display == tbl
      puml_lines << "class #{tbl}"
    else
      puml_lines << "class \"#{display}\" as #{tbl}"
    end
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
    "SELECT t.table_name, c.column_name, c.data_type, c.is_nullable, CASE WHEN pk.column_name IS NOT NULL THEN 'YES' ELSE 'NO' END AS is_primary_key FROM information_schema.tables t LEFT JOIN information_schema.columns c ON t.table_name = c.table_name AND t.table_schema = c.table_schema LEFT JOIN (SELECT ku.table_name, ku.column_name FROM information_schema.table_constraints tc JOIN information_schema.key_column_usage ku ON tc.constraint_name = ku.constraint_name WHERE tc.constraint_type = 'PRIMARY KEY' AND tc.table_schema = $1) pk ON t.table_name = pk.table_name AND c.column_name = pk.column_name WHERE t.table_schema = $1 ORDER BY t.table_name, c.ordinal_position;",
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

conn.close