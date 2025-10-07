#!/usr/bin/env ruby
# Единый конвертер OpenAPI/Swagger в AsciiDoc документацию
# Источники задаются в файле sources.yml

require 'json'
require 'open-uri'
require 'yaml'
require 'fileutils'

$t_counter = 0

# Загружаем конфигурацию источников
def load_sources_config(config_file = 'sources.yml')
  # Если передан абсолютный путь, используем его
  if File.absolute_path?(config_file)
    config_path = config_file
  else
    # Ищем файл конфигурации в директории скрипта
    config_path = File.join(__dir__, config_file)
  end
  
  unless File.exist?(config_path)
    puts "❌ Файл конфигурации #{config_path} не найден!"
    puts "�� Создайте файл sources.yml с настройками источников"
    exit 1
  end
  
  YAML.safe_load(File.read(config_path))
end

# Загружаем схемы
def load_schemas(api)
  api.dig('components', 'schemas') || api.dig('definitions') || {}
end

# Разворачиваем $ref
def resolve_ref(ref, schemas)
  ref.split('/').last.then { |key| schemas[key] || {} }
end

# Цветовое кодирование HTTP методов
def get_method_color(method)
  case method.upcase
  when 'GET'
    'green'
  when 'POST'
    'blue'
  when 'PUT'
    'orange'
  when 'DELETE'
    'red'
  when 'PATCH'
    'purple'
  else
    'gray'
  end
end

# Создание красивого блока для HTTP метода
def create_method_block(method, path)
  color = get_method_color(method)
  <<~BLOCK
    [#{method.downcase}-#{path.gsub(/[^a-zA-Z0-9]/, '-')}]
    [source,http,role="http-method-#{color}"]
    ----
    #{method.upcase} #{path}
    ----
  BLOCK
end

# Создание блока для статус-кода
def create_status_block(status, description)
  status_class = case status.to_i
  when 200..299
    'success'
  when 300..399
    'info'
  when 400..499
    'warning'
  when 500..599
    'error'
  else
    'default'
  end
  
  <<~BLOCK
    [#{status}-#{status_class}]
    [source,http,role="status-#{status_class}"]
    ----
    #{status} #{description}
    ----
  BLOCK
end

def insert_table_header(doc, title, cols = "2,2,2,4", headers = "|Имя |Тип |Формат |Описание")
  $t_counter += 1
  doc.puts ""
  doc.puts ":t_num: {counter:table-number}"
  if title == "Параметры запроса"
    doc.puts "Параметры запроса приведены в таблице {t_num}."
  else
    doc.puts "#{title} приведена в таблице {t_num}."
  end
  doc.puts ""
  doc.puts "[#id_t_{t_num}]"
  doc.puts ".Таблица {t_num}. #{title}"
  doc.puts "[options=\"header\", cols=\"#{cols}\"]"
  doc.puts "|==="
  doc.puts headers.gsub('|', '^|')
end

# Улучшенная таблица свойств объекта с детальным описанием
def write_schema_properties(doc, schema, schemas)
  required_props = schema['required'] || []
  
  if schema['properties']
    schema['properties'].each do |prop_name, prop_info|
      if prop_info['$ref']
        ref_schema = resolve_ref(prop_info['$ref'], schemas)
        type = ref_schema['type'] || 'object'
        format = '-'
        description = ref_schema['description'] || '-'
      else
        # Улучшенная обработка массивов
        if prop_info['type'] == 'array' && prop_info['items']
          item_type = prop_info['items']['type'] || 'object'
          item_format = prop_info['items']['format'] || '-'
          type = "array of #{item_type}"
          format = item_format
        else
          type = prop_info['type'] || 'object'
          format = prop_info['format'] || '-'
        end
        description = prop_info['description'] || '-'
      end
      required_marker = required_props.include?(prop_name) ? '*' : ''
      doc.puts "|#{prop_name}#{required_marker} |#{type} |#{format} |#{description}"
    end
  else
    doc.puts "| _Нет описания свойств_ | | |"
  end
  doc.puts "|==="
  doc.puts ""
  
  # Детальное описание свойств после таблицы
  if schema['properties']
    doc.puts "=== Детальное описание свойств"
    doc.puts ""
    schema['properties'].each do |prop_name, prop_info|
      doc.puts "==== #{prop_name}"
      doc.puts ""
      
      # Основная информация
      doc.puts "Тип: #{get_detailed_type(prop_info, schemas)}"
      doc.puts ""
      
      # Описание
      if prop_info['description'] && !prop_info['description'].empty?
        doc.puts "Описание: #{prop_info['description']}"
        doc.puts ""
      end
      
      # Обязательность
      required_props = schema['required'] || []
      if required_props.include?(prop_name)
        doc.puts "Обязательность: Обязательный параметр"
      else
        doc.puts "Обязательность: Необязательный параметр"
      end
      doc.puts ""
      
      # Значение по умолчанию
      if prop_info['default']
        doc.puts "Значение по умолчанию: `#{prop_info['default']}`"
        doc.puts ""
      end
      
      # Enum значения
      if prop_info['enum']
        doc.puts "Допустимые значения:"
        doc.puts ""
        prop_info['enum'].each do |value|
          doc.puts ". #{value}"
        end
        doc.puts ""
      end
      
      # Минимальные/максимальные значения
      if prop_info['minimum']
        doc.puts "Минимальное значение: #{prop_info['minimum']}"
        doc.puts ""
      end
      if prop_info['maximum']
        doc.puts "Максимальное значение: #{prop_info['maximum']}"
        doc.puts ""
      end
      
      # Длина строки
      if prop_info['minLength']
        doc.puts "Минимальная длина: #{prop_info['minLength']}"
        doc.puts ""
      end
      if prop_info['maxLength']
        doc.puts "Максимальная длина: #{prop_info['maxLength']}"
        doc.puts ""
      end
      
      # Паттерн для строк
      if prop_info['pattern']
        doc.puts "Паттерн: `#{prop_info['pattern']}`"
        doc.puts ""
      end
      
      # Примеры
      if prop_info['example']
        doc.puts "Пример:"
        doc.puts ""
        doc.puts "[source,json]"
        doc.puts "----"
        doc.puts JSON.pretty_generate(prop_info['example'])
        doc.puts "----"
        doc.puts ""
      end
      
      doc.puts ""
    end
  end
  
  # Дополнительные свойства
  if schema.key?('additionalProperties')
    doc.puts "=== Дополнительные свойства"
    doc.puts ""
    case schema['additionalProperties']
    when false
      doc.puts "Указано свойство `\"additionalProperties\": false` – дополнительные свойства не разрешены."
    when true
      doc.puts "Указано свойство `\"additionalProperties\": true` – дополнительные свойства разрешены."
    else
      doc.puts "Дополнительные свойства разрешены и описаны отдельно."
    end
    doc.puts ""
  end
end

# Получение детального типа
def get_detailed_type(prop_info, schemas)
  if prop_info['$ref']
    ref_schema = resolve_ref(prop_info['$ref'], schemas)
    type = ref_schema['type'] || 'object'
    format = ref_schema['format'] || ''
    format.empty? ? type : "#{type} (#{format})"
  elsif prop_info['type'] == 'array' && prop_info['items']
    item_type = prop_info['items']['type'] || 'object'
    item_format = prop_info['items']['format'] || ''
    format_str = item_format.empty? ? '' : " (#{item_format})"
    "array of #{item_type}#{format_str}"
  else
    type = prop_info['type'] || 'object'
    format = prop_info['format'] || ''
    format.empty? ? type : "#{type} (#{format})"
  end
end

# Получение типа и формата параметра
def parameter_type(param, schemas)
  if param['schema']
    if param['schema']['$ref']
      resolve_ref(param['schema']['$ref'], schemas)['type'] || 'object'
    else
      param['schema']['type'] || 'unknown'
    end
  else
    param['type'] || 'unknown'
  end
end

def parameter_format(param)
  if param['schema']
    param['schema']['format'] || '-'
  else
    param['format'] || '-'
  end
end

# Детальное описание параметров
def write_parameter_details(doc, param, schemas)
  doc.puts "==== #{param['name']}"
  doc.puts ""
  
  # Основная информация
  doc.puts "Тип: #{parameter_type(param, schemas)}"
  doc.puts ""
  
  # Формат
  format = parameter_format(param)
  if format != '-'
    doc.puts "Формат: #{format}"
    doc.puts ""
  end
  
  # Описание
  if param['description'] && !param['description'].empty?
    doc.puts "Описание: #{param['description']}"
    doc.puts ""
  end
  
  # Обязательность
  if param['required']
    doc.puts "Обязательность: Обязательный параметр"
  else
    doc.puts "Обязательность: Необязательный параметр"
  end
  doc.puts ""
  
  # Расположение параметра
  if param['in']
    doc.puts "Расположение: #{param['in']}"
    doc.puts ""
  end
  
  # Enum значения
  if param['schema'] && param['schema']['enum']
    doc.puts "Допустимые значения:"
    doc.puts ""
    param['schema']['enum'].each do |value|
      doc.puts ". #{value}"
    end
    doc.puts ""
  end
  
  # Примеры
  if param['example']
    doc.puts "Пример:"
    doc.puts ""
    doc.puts "[source,json]"
    doc.puts "----"
    doc.puts JSON.pretty_generate(param['example'])
    doc.puts "----"
    doc.puts ""
  end
  
  doc.puts ""
end

def generate_adoc(api, schemas, output_file)
  File.open(output_file, 'w') do |doc|
    doc.puts ":!chapter-signifier:"
    doc.puts ":figure-caption!:"
    doc.puts ":table-caption!:"
    doc.puts ":doctype: book"
    doc.puts ":icons: font"
    doc.puts ":toc: macro"
    doc.puts ":toc-title: Содержание"
    doc.puts ":toclevels: 3"
    doc.puts ":sectnums:"
    doc.puts ":sectnumlevels: 5"
    doc.puts ":imagesdir: ./images"
    doc.puts ":docinfo: shared"
    doc.puts ":source-highlighter: rouge"
    doc.puts ":rouge-css: style"

    doc.puts ""
    doc.puts "= #{api['info']['title']}"
    doc.puts ""

    doc.puts ""
    doc.puts "ifndef::env-antora[]"
    doc.puts ""
    doc.puts "<<<<"
    doc.puts "toc::[]"
    doc.puts "<<<<"
    doc.puts "endif::[]"

    doc.puts ""
    doc.puts "== Общие сведения"
    doc.puts ""

    # Красивый блок с информацией об API
    doc.puts "[source,yaml,role='api-info']"
    doc.puts "----"
    doc.puts "title: #{api['info']['title']}"
    doc.puts "version: #{api['info']['version']}"
    doc.puts "openapi: #{api['openapi'] || api['swagger']}"
    if api['info']['description']
      doc.puts "description: #{api['info']['description']}"
    end
    doc.puts "----"
    doc.puts ""

    # Контактная информация
    if api['info']['contact']
      doc.puts "=== Контактная информация"
      doc.puts ""
      if api['info']['contact']['name']
        doc.puts "Имя: #{api['info']['contact']['name']}"
      end
      if api['info']['contact']['email']
        doc.puts "Email: #{api['info']['contact']['email']}"
      end
      if api['info']['contact']['url']
        doc.puts "URL: #{api['info']['contact']['url']}"
      end
      doc.puts ""
    end

    # Лицензия
    if api['info']['license']
      doc.puts "=== Лицензия"
      doc.puts ""
      doc.puts "Название: #{api['info']['license']['name']}"
      if api['info']['license']['url']
        doc.puts "URL: #{api['info']['license']['url']}"
      end
      doc.puts ""
    end

    # Серверы
    if api['servers'] || api['host']
      doc.puts "=== Серверы"
      doc.puts ""
      if api['servers']
        api['servers'].each do |server|
          doc.puts "* #{server['url']}"
          if server['description']
            doc.puts "  #{server['description']}"
          end
        end
      elsif api['host']
        base_path = api['basePath'] || ''
        schemes = api['schemes'] || ['https']
        schemes.each do |scheme|
          doc.puts "* #{scheme}://#{api['host']}#{base_path}"
        end
      end
      doc.puts ""
    end

    doc.puts ""
    
    doc.puts "<<<<"
    doc.puts "== Эндпоинты"
    doc.puts ""

    endpoints = []

    api['paths'].each do |path, methods|
      methods.each do |http_method, details|
        summary = details['summary'] || '-'
        endpoints << [http_method.upcase, path, summary]
      end
    end

    insert_table_header(doc, "Перечень эндпоинтов", "2,4,6", "|Метод |Путь |Описание")

    endpoints.each do |method, path, summary|
      doc.puts "|#{method} |#{path} |#{summary}"
    end

    doc.puts "|==="
    doc.puts ""

    api['paths'].each do |path, methods|
      methods.each do |http_method, details|
        # Красивый блок с HTTP методом
        doc.puts create_method_block(http_method, path)
        doc.puts ""

        # Описание эндпоинта
        if details['summary']
          doc.puts "Описание: #{details['summary']}"
          doc.puts ""
        end
        
        if details['description']
          doc.puts "Детальное описание: #{details['description']}"
          doc.puts ""
        end

        if details['tags'] && details['tags'].any?
          doc.puts "Теги: #{details['tags'].join(', ')}"
          doc.puts ""
        end

        # Параметры
        if details['parameters']&.any?
          doc.puts "=== Параметры запроса"
          doc.puts ""
          insert_table_header(doc, "Параметры запроса")
          details['parameters'].each do |param|
            name = param['name']
            type = parameter_type(param, schemas)
            format = parameter_format(param)
            description = param['description'] || '-'
            doc.puts "|#{name} |#{type} |#{format} |#{description}"
          end
          doc.puts "|==="
          doc.puts ""
          
          # Детальное описание параметров
          doc.puts "=== Детальное описание параметров"
          doc.puts ""
          details['parameters'].each do |param|
            write_parameter_details(doc, param, schemas)
          end
          
          # Enum значения для $ref параметров
          details['parameters'].each do |param|
            schema = param['schema']
            next unless schema

            ref = if schema['$ref']
                    schema['$ref']
                  elsif schema['type'] == 'array' && schema['items'] && schema['items']['$ref']
                    schema['items']['$ref']
                  else
                    nil
                  end

            if ref
              enum_schema = resolve_ref(ref, schemas)
              if enum_schema['enum']
                doc.puts "===== Перечень значений #{param['name']}"
                doc.puts ""
                enum_schema['enum'].each do |value|
                  doc.puts ". #{value}"
                end
                doc.puts ""
              end
            end
          end
        else
          doc.puts "Параметры запроса отсутствуют."
          doc.puts ""
        end

        # Тело запроса
        if details['requestBody']
          doc.puts "=== Тело запроса"
          doc.puts ""
          doc.puts "* Тело запроса:"
          doc.puts ""
          content = details['requestBody']['content']
          ref_groups = {}

          content&.each do |mime, body|
            schema = body['schema']
            next unless schema

            ref = if schema['$ref']
                    schema['$ref']
                  elsif schema['type'] == 'array' && schema['items'] && schema['items']['$ref']
                    schema['items']['$ref']
                  else
                    nil
                  end

            if ref
              ref_groups[ref] ||= []
              ref_groups[ref] << mime
            else
              # Для схем без $ref выводим отдельно
              doc.puts "** MIME-тип: #{mime}"
              if schema['type']
                doc.puts "_Тело простого типа: #{schema['type']}_"
              else
                doc.puts "Описание структуры тела запроса отсутствует или неизвестно."
              end
              doc.puts ""
            end
          end

          ref_groups.each do |ref, mimes|
            schema_name = ref.split('/').last
            ref_schema = resolve_ref(ref, schemas)

            if mimes.size == 1
              doc.puts "** MIME-тип: #{mimes.first}"
            else
              doc.puts "** MIME-типы: #{mimes.join(', ')}"
            end
            doc.puts "Ответ «#{schema_name}»"
            insert_table_header(doc, "Схема тела запроса «#{schema_name}»")

            if ref_schema['description']
              doc.puts "Описание модели данных: #{ref_schema['description']}."
              doc.puts ""
            end

            write_schema_properties(doc, ref_schema, schemas)
            doc.puts ""
          end
        end

        # Ответы
        if details['responses']&.any?
          doc.puts "=== Ответы сервера"
          doc.puts ""
          doc.puts "Возможные ответы сервера:"
          doc.puts ""
          
          # Красивые блоки для статус-кодов
          details['responses'].each do |status, response|
            description = response['description']&.strip
            description = 'Без описания' if description.nil? || description.empty?
            doc.puts create_status_block(status, description)
            doc.puts ""
          end
          
        end

        doc.puts ""
      end
      doc.puts ""
    end
  end
end

# Обработка одного источника
def process_source(source, settings, output_dir)
  source_path = source['path']
  source_type = source['type']
  description = source['description'] || source_path
  
  puts "📝 Обрабатываем: #{description}"
  
  begin
    if source_type == 'url'
      puts "  �� Скачиваем JSON с #{source_path}..."
      content = URI.open(source_path).read
      
      if source_path.end_with?('.yaml', '.yml')
        api = YAML.safe_load(content)
      else
        api = JSON.parse(content)
      end
      
      url_part = source_path.sub(%r{^https?://}, '').gsub(%r{[:/]}, '_').gsub(/\?.*/, '').sub(/\.json$/, '')
      short_name = url_part.split('.').first
      output_file = "#{output_dir}/#{short_name}#{settings['output_suffix']}.adoc"
      
    elsif source_type == 'file'
      puts "  📄 Обрабатываем файл: #{source_path}"
      
      unless File.exist?(source_path)
        puts "  ❌ Файл не найден: #{source_path}"
        return
      end
      
      if source_path.end_with?('.yaml', '.yml')
        api = YAML.safe_load(File.read(source_path, encoding: 'UTF-8'))
      else
        api = JSON.parse(File.read(source_path, encoding: 'UTF-8'))
      end
      
      base_name = File.basename(source_path, '.*')
      short_name = base_name.split('.').first
      output_file = "#{output_dir}/#{short_name}#{settings['output_suffix']}.adoc"
      
    elsif source_type == 'directory'
      puts "  📁 Обрабатываем папку: #{source_path}"
      
      unless Dir.exist?(source_path)
        puts "  ❌ Папка не найдена: #{source_path}"
        return
      end
      
      patterns = source['patterns'] || ['*.json', '*.yaml', '*.yml']
      files_found = false
      
      patterns.each do |pattern|
        Dir.glob(File.join(source_path, pattern)).each do |file_path|
          files_found = true
          puts "    📄 Файл: #{file_path}"
          
          if file_path.end_with?('.yaml', '.yml')
            api = YAML.safe_load(File.read(file_path, encoding: 'UTF-8'))
          else
            api = JSON.parse(File.read(file_path, encoding: 'UTF-8'))
          end
          
          schemas = load_schemas(api)
          base_name = File.basename(file_path, '.*')
          short_name = base_name.split('.').first
          output_file = "#{output_dir}/#{short_name}#{settings['output_suffix']}.adoc"
          
          generate_adoc(api, schemas, output_file)
          puts "    ✅ Готово: #{output_file}"
        end
      end
      
      unless files_found
        puts "  ⚠️  Файлы не найдены в папке #{source_path}"
      end
      return
      
    else
      puts "  ❌ Неизвестный тип источника: #{source_type}"
      return
    end
    
    # Генерируем документацию для URL и отдельных файлов
    schemas = load_schemas(api)
    generate_adoc(api, schemas, output_file)
    puts "  ✅ Готово: #{output_file}"
    
  rescue => e
    puts "  ❌ Ошибка при обработке #{source_path}: #{e.message}"
  end
  
  puts ""
end

# Парсинг аргументов командной строки
require 'optparse'

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: openapi_to_adoc.rb [options]"

  opts.on("--sources SOURCES_FILE", "Path to sources.yml file") do |sources|
    options[:sources] = sources
  end

  opts.on("--in INPUT_DIR", "Input directory") do |in_dir|
    options[:in] = in_dir
  end

  opts.on("--out OUTPUT_DIR", "Output directory") do |out_dir|
    options[:out] = out_dir
  end
end.parse!

# Основная логика
puts "🚀 Генерация документации API"
puts "📋 Конфигурация загружается из sources.yml"
puts ""

# Загружаем конфигурацию
sources_file = options[:sources] || 'sources.yml'
config = load_sources_config(sources_file)
sources = config['sources'] || []
settings = config['settings'] || {}

# Создаем папку для выходных файлов
output_dir = options[:out] || File.join(__dir__, 'api-adoc')
FileUtils.mkdir_p(output_dir) unless Dir.exist?(output_dir)
puts "📁 Создана папка для документации: #{output_dir}/"
puts ""

if sources.empty?
  puts "❌ Источники не найдены в конфигурации!"
  puts "📝 Добавьте источники в файл sources.yml"
  exit 1
end

puts "�� Найдено источников: #{sources.size}"
sources.each_with_index do |source, index|
  puts "  #{index + 1}. #{source['description'] || source['path']} (#{source['type']})"
end
puts ""

# Обрабатываем каждый источник
sources.each_with_index do |source, index|
  puts "📝 Обрабатываем источник #{index + 1}/#{sources.size}"
  process_source(source, settings, output_dir)
end

puts "🎉 Все источники обработаны!"