#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'pathname'

# Загружаем наши модули
require_relative 'lib/utils'
require_relative 'lib/config_parser'
require_relative 'lib/pdf_generator'
require_relative 'lib/specification_generator'
require_relative 'lib/asciidoc_linter'

# Настройки
KROKI_URL = ENV.fetch('KROKI_SERVER_URL', 'http://localhost:8000')
CFG_PATH = 'tools/config.yml'
COMPONENT_FILTER = ARGV[0]  # Опциональный фильтр по имени компонента

# Загружаем конфигурацию
cfg = ConfigParser.load_config(CFG_PATH)

# Для некоторых задач (lint) важно запускать один раз на компонент,
# даже если в config.yml есть несколько записей одного и того же компонента.
components = cfg['components']
last_index_by_name = {}
components.each_with_index do |c, idx|
  next if COMPONENT_FILTER && c['name'] != COMPONENT_FILTER
  last_index_by_name[c['name']] = idx
end

# Получаем пути к скриптам
scripts_dir = File.expand_path("../scripts", __FILE__)
bpmn_js   = File.join(scripts_dir, "bpmn_to_img.js")
drawio_js = File.join(scripts_dir, "drawio_to_img.js")
api_rb    = File.join(scripts_dir, "openapi-swagger-adoc.rb")
bd_rb     = File.join(scripts_dir, "db_to_adoc.rb")

puts "\n****************************  Выполнение команд  **************************************\n"
puts "KROKI_SERVER_URL: #{KROKI_URL}"
puts "Конфигурация: #{CFG_PATH}"
if ENV['CI']
  puts "🔧 Режим CI: генерация диаграмм, API и БД отключена"
end
start_time = Time.now

# Обрабатываем каждый компонент
lint_results = []
should_generate_lists = false
components.each_with_index do |comp, idx|
  name = comp['name']
  
  # Фильтрация по имени компонента, если указан аргумент
  next if COMPONENT_FILTER && name != COMPONENT_FILTER
  
  puts "=== Обработка компонента: #{name} ==="
  
  # 1. Конвертация BPMN
  diagram_settings = ConfigParser.get_diagram_settings(comp, cfg)
  # В CI отключаем генерацию диаграмм (нет Chrome и Draw.io)
  if ENV['CI']
    diagram_settings[:bpmn_enabled] = false
    diagram_settings[:drawio_enabled] = false
  end
  
  if diagram_settings[:bpmn_enabled]
    puts "  -> bpmn: #{diagram_settings[:bpmn_src]} -> #{diagram_settings[:bpmn_dst]}"
    Utils.prepare_destination_dir(diagram_settings[:bpmn_dst], diagram_settings[:bpmn_erase_folder])
    system(%(node "#{bpmn_js}" --in "#{diagram_settings[:bpmn_src]}" --out "#{diagram_settings[:bpmn_dst]}" --format svg))
  end

  # 2. Конвертация Drawio
  if diagram_settings[:drawio_enabled]
    puts "  -> drawio: #{diagram_settings[:drawio_src]} -> #{diagram_settings[:drawio_dst]}"
    Utils.prepare_destination_dir(diagram_settings[:drawio_dst], diagram_settings[:drawio_erase_folder])
    system(%(node "#{drawio_js}" --in "#{diagram_settings[:drawio_src]}" --out "#{diagram_settings[:drawio_dst]}" --format svg))
  end

  # 3. Конвертация API
  api_settings = ConfigParser.get_api_settings(comp, cfg, name)
  # В CI отключаем генерацию API (нет доступа к источникам)
  if ENV['CI']
    api_settings[:enabled] = false
  end
  
  if api_settings[:enabled]
    puts "  -> api: #{api_settings[:dst]}"
    puts "  -> sources: #{api_settings[:sources_file]}"
    
    # Подготавливаем директорию назначения
    Utils.prepare_destination_dir(api_settings[:dst], api_settings[:erase_folder])
    
    if File.exist?(api_settings[:sources_file])
      sources_abs_path = File.expand_path(api_settings[:sources_file])
      system(%(ruby "#{api_rb}" --sources "#{sources_abs_path}" --out "#{api_settings[:dst]}"))
    else
      puts "  ❌ Файл источников API не найден: #{api_settings[:sources_file]}"
    end
  end

  # 4. Конвертация БД
  db_settings = ConfigParser.get_db_settings(comp, cfg, name)
  # В CI отключаем генерацию БД (нет доступа к базе данных)
  if ENV['CI'] && db_settings
    db_settings[:enabled] = false
  end
  
  if db_settings && db_settings[:enabled]
    puts "  -> bd(#{db_settings[:profile]}): #{db_settings[:connection]['host']}:#{db_settings[:connection]['port']}/#{db_settings[:connection]['db']} -> #{db_settings[:dst]}"
    puts "  -> bd_images: -> #{db_settings[:images_dir]}"
    
    # Подготавливаем директории назначения
    Utils.prepare_destination_dir(db_settings[:dst], db_settings[:erase_folder])
    Utils.prepare_destination_dir(db_settings[:images_dir], db_settings[:erase_folder])
    
    system(%(ruby "#{bd_rb}" --component "#{name}" --host "#{db_settings[:connection]['host']}" --port "#{db_settings[:connection]['port']}" --db "#{db_settings[:connection]['db']}" --user "#{db_settings[:connection]['user']}" --pass "#{db_settings[:connection]['pass']}" --out "#{db_settings[:dst]}" --images "#{db_settings[:images_dir]}" --use-llm))
    
    # Изображения созданы в docs-db/, Antora будет использовать их оттуда
    puts "  -> images: PNG файлы созданы в #{db_settings[:images_dir]}"
  end

  # 4.1. Генерация таблиц спецификации и ведомости (до генерации PDF, чтобы таблицы были готовы для включения в документы)
  pdf_settings = ConfigParser.get_pdf_settings(comp, cfg)
  if pdf_settings[:enabled] && pdf_settings[:generate_specification]
    SpecificationGenerator.generate_for_component(comp, cfg)
  end

  # 5. Генерация PDF
  PdfGenerator.generate_pdfs(comp, KROKI_URL, cfg)

  # 6. Генерация списков файлов
  list_settings = ConfigParser.get_list_settings(comp['name'], cfg, cfg['components'])
  if list_settings[:enabled] && (list_settings[:adoc_lists] || list_settings[:pdf_lists])
    # puts "  -> list: генерация списков файлов"
    should_generate_lists = true
  end

  # 7. Asciidoctor lint (только логи, без падения сборки)
  if last_index_by_name[name] == idx
    begin
      result = AsciidocLinter.lint_component(comp, cfg)
      lint_results << result if result&.ran
      if result&.ran
        if !result.asciidoctor_available
          puts "  ⚠️  asciidoctor lint: asciidoctor CLI не найден (лог: #{result.log_path})"
        elsif result.files_with_messages > 0
          puts "  ⚠️  asciidoctor lint: #{result.errors} ERROR / #{result.warnings} WARNING (лог: #{result.log_path})"
        else
          puts "  ✅ asciidoctor lint: ошибок не найдено (#{result.files_scanned} файлов)"
        end
      end
    rescue => e
      puts "  ⚠️  asciidoctor lint: ошибка выполнения: #{e.message}"
    end
  end
end

# 6. Генерация списков файлов (один раз на запуск, т.к. генератор обрабатывает все компоненты)
if should_generate_lists
  system(%(ruby "tools/scripts/generate_lists.rb"))
end

end_time = Time.now
execution_time = end_time - start_time
minutes = (execution_time / 60).to_i
seconds = (execution_time % 60).to_i

puts "*************************** Все команды выполнены ****************************"

# Итоговая сводка по lint-логам
if lint_results.any?
  # Дедуплицируем по компоненту (на случай нескольких записей одного компонента в конфиге)
  latest_by_component = {}
  lint_results.each { |r| latest_by_component[r.component] = r }

  updated = latest_by_component.values.select { |r| r.log_updated }
  with_issues = latest_by_component.values.select { |r| r.asciidoctor_available && r.files_with_messages.to_i > 0 }
  missing_cli = latest_by_component.values.select { |r| !r.asciidoctor_available }

  puts "\n=== Asciidoctor lint summary ==="
  puts "Компонентов проверено: #{latest_by_component.values.size}"
  puts "Логи обновились: #{updated.size}"
  puts "Компонентов с проблемами: #{with_issues.size}"
  puts "Компонентов без asciidoctor CLI: #{missing_cli.size}"

  if updated.any?
    puts "\nОбновленные логи:"
    updated.each do |r|
      puts "  - #{r.component}: #{r.errors} ERROR / #{r.warnings} WARNING (#{r.files_with_messages}/#{r.files_scanned} файлов) – #{r.log_path}"
    end
  end

  if with_issues.any?
    puts "\nКомпоненты с ошибками/предупреждениями:"
    with_issues.each do |r|
      puts "  - #{r.component}: #{r.errors} ERROR / #{r.warnings} WARNING – #{r.log_path}"
    end
  end

  if missing_cli.any?
    puts "\nКомпоненты без установленного asciidoctor:"
    missing_cli.each do |r|
      puts "  - #{r.component}: #{r.log_path}"
    end
  end
end

commit_hash = `git log -1 --format=%H`.strip
puts "✅ Хеш последнего коммита: #{commit_hash}"
puts "Время начала: #{start_time.strftime('%Y-%m-%d %H:%M:%S')}"
puts "Время окончания: #{end_time.strftime('%Y-%m-%d %H:%M:%S')}"
puts "Общее время: #{execution_time.round(2)} сек (или #{minutes} мин #{seconds} сек)"
