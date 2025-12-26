#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

# Генератор списков файлов для навигации компонентов
# Автоматически создает ROOT/partials/list-pages-component.adoc
# и добавляет include в ROOT/nav.adoc

require 'yaml'
require 'fileutils'
require 'pathname'

class ListGenerator
  def initialize(config_path = 'tools/config.yml')
    @config_path = config_path
    @config = load_config
  end

  def generate_all_components
    puts "🔄 Генерация списков для всех компонентов..."
    
    components = @config['components'] || []
    component_names = components.map { |c| c['name'] }.uniq

    component_names.each do |component_name|
      next unless list_enabled_for_component_name?(component_name, components)

      puts "Обработка компонента: #{component_name}"

      generate_component_list({ 'name' => component_name })
      update_nav_with_include(component_name)
    end

    # puts "✅ Генерация завершена!"
  end

  def generate_component_list(component)
    component_name = component['name']
    components_dir = File.dirname(@config_path).gsub('tools', 'components')
    component_dir = File.join(components_dir, component_name)
    
    unless Dir.exist?(component_dir)
      puts "⚠️  Компонент #{component_name} не найден: #{component_dir}"
      return false
    end

    # Генерируем список .adoc файлов (навигацию)
    # if generate_adoc_list(component, component_name, component_dir)
    #   puts "✅ Список .adoc файлов сгенерирован для #{component_name}"
    # else
    #   puts "❌ Ошибка генерации списка .adoc для #{component_name}"
    # end
    generate_adoc_list(component, component_name, component_dir)

    # Генерируем список .pdf файлов  
    if generate_pdf_list(component, component_name, component_dir)
      puts "✅ Список .pdf файлов сгенерирован для #{component_name}"
    # else
    #   puts "⚠️  PDF файлы не найдены для #{component_name}"
    end

    true
  end

  # Генерирует список .adoc файлов (навигацию)
  def generate_adoc_list(component, component_name, component_dir)
    # Собираем все файлы из всех модулей
    files_by_module = collect_files_by_module(component_dir, component)
    
    # Генерируем навигацию
    navigation_content = generate_navigation_content(files_by_module, component_name)
    
    # Получаем настройки списков для правильного пути сохранения
    list_settings = get_list_settings_for_component(component_name)
    dst_path = list_settings[:dst]
    
    # Расширяем путь с переменной {name}
    expanded_dst = dst_path.gsub('{name}', component_name)
    
    # Создаем папку назначения
    FileUtils.mkdir_p(expanded_dst) unless Dir.exist?(expanded_dst)
    
    # Сохраняем файл навигации
    output_file = File.join(expanded_dst, 'list-pages-component.adoc')
    File.write(output_file, navigation_content, encoding: 'UTF-8')
    
    puts "✅ Сгенерирован файл навигации: #{output_file}"
    true
  end

  # Генерирует список .pdf файлов
  def generate_pdf_list(component, component_name, component_dir)
    # Получаем настройки списков
    list_settings = get_list_settings_for_component(component_name)
    
    # Проверяем, нужно ли генерировать PDF списки
    return false unless list_settings[:pdf_lists]
    
    # Определяем папку с PDF файлами
    pdf_src_path = list_settings[:pdf_src].gsub('{name}', component_name)
    
    # Проверяем существование папки attachments, создаем если нет
    unless Dir.exist?(pdf_src_path)
      # puts "📂 Папка PDF не найдена: #{pdf_src_path}"
      # puts "📁 Создаем папку для продолжения работы"
      FileUtils.mkdir_p(pdf_src_path)
    end
    
    # Сканируем PDF файлы
    pdf_files = Dir.glob(File.join(pdf_src_path, '*.pdf')).sort
    
    # Определяем папку назначения
    dst_path = list_settings[:dst].gsub('{name}', component_name)
    FileUtils.mkdir_p(dst_path) unless Dir.exist?(dst_path)
    
    # Сохраняем файлы списков PDF (обычный и табличный)
    output_file = File.join(dst_path, 'list-pdf-component.adoc')
    output_table_file = File.join(dst_path, 'list-pdf-component-table.adoc')
    
    if pdf_files.empty?
      # Создаем файлы с атрибутом для условного отображения
      pdf_list_content = ":list_pdf_file_is_empty:\n\n"
      File.write(output_file, pdf_list_content, encoding: 'UTF-8')
      File.write(output_table_file, pdf_list_content, encoding: 'UTF-8')
      # puts "📄 Созданы пустые списки PDF файлов с атрибутом: #{output_file} и #{output_table_file}"
    else
      # Генерируем содержимое списков PDF (обычный и табличный)
      pdf_list_lines = pdf_files.map.with_index { |pdf_file, index| generate_pdf_list_content(pdf_file, index) }
      pdf_list_content = pdf_list_lines.join("\n") + "\n"
      pdf_table_content = generate_pdf_table_content(pdf_files)
      File.write(output_file, pdf_list_content, encoding: 'UTF-8')
      File.write(output_table_file, pdf_table_content, encoding: 'UTF-8')
      # puts "✅ Сгенерированы файлы списков PDF: #{output_file} и #{output_table_file}"
    end
    
    true
  end

  private

  def load_config
    unless File.exist?(@config_path)
      puts "❌ Конфигурационный файл не найден: #{@config_path}"
      exit 1
    end
    
    YAML.load_file(@config_path, aliases: true)
  rescue => e
    puts "❌ Ошибка чтения конфига: #{e.message}"
    exit 1
  end

  def list_enabled?(component)
    list_config = (@config.dig('defaults', 'list') || {}).merge(component['list'] || {})
    list_config && list_config['enabled'] == true && (list_config['adoc_lists'] != false || list_config['pdf_lists'] == true)
  end

  def list_enabled_for_component_name?(component_name, all_components)
    # Объединяем настройки list из всех записей компонента с одинаковым именем
    merged = (@config.dig('defaults', 'list') || {}).dup
    all_components.select { |c| c['name'] == component_name }.each do |entry|
      merged.merge!(entry['list']) if entry['list']
    end

    merged['enabled'] == true && (merged['adoc_lists'] != false || merged['pdf_lists'] == true)
  end

  def collect_files_by_module(component_dir, component)
    files_by_module = {}
    
    # Паттерн для поиска: components/{name}/modules/{module}/pages/*.adoc
    modules_pattern = File.join(component_dir, 'modules', '*', 'pages', '*.adoc')
    
    Dir.glob(modules_pattern) do |file_path|
      # Извлекаем модуль из пути
      path_parts = Pathname.new(file_path).each_filename.to_a
      module_index = path_parts.index('modules')
      next unless module_index && module_index + 2 < path_parts.length
      
      module_name = path_parts[module_index + 1]
      file_name = File.basename(file_path, '.adoc')
      
      files_by_module[module_name] ||= []
      files_by_module[module_name] << {
        name: file_name,
        path: file_path,
        title: generate_file_title(file_name, file_path)
      }
    end
    
    files_by_module
  end

  def generate_file_title(file_name, file_path)
    # Пытаемся извлечь заголовок из AsciiDoc файла
    title = extract_title_from_adoc(file_path)
    
    # Если заголовок не найден, используем имя файла
    if title.nil? || title.empty?
      base_name = file_name.split('.').first
      title = base_name.gsub('_', ' ')
      # puts "📄 Используется имя файла для #{file_name}: #{title}"
    # else
    #   puts "📄 Извлечен заголовок для #{file_name}: #{title}"
    end
    
    title
  end

  def extract_title_from_adoc(file_path)
    return nil unless File.exist?(file_path)
    
    begin
      content = File.read(file_path, encoding: 'UTF-8')
      
      # Сначала извлекаем значение атрибута name_document_master
      name_document_master = nil
      if content.match(/^:name_document_master:\s*(.+)$/)
        name_document_master = $1.strip
      end
      
      # Ищем заголовок первого уровня (= Title)
      # Ограничиваем поиск только первой строкой после =
      if content.match(/^= ([^\n\r]+)/)
        title = $1.strip
        # Убираем атрибуты, если они есть (например, = Title :attr:)
        title = title.split(':').first.strip
        # Убираем комментарии, если они есть
        title = title.split('//').first.strip
        # Убираем лишние пробелы
        title = title.gsub(/\s+/, ' ').strip
        
        # Если заголовок содержит {name_document_master} и мы нашли значение атрибута, заменяем
        if title == '{name_document_master}' && name_document_master
          return name_document_master
        end
        
        return title
      end
      
      nil
    rescue => e
      puts "⚠️  Ошибка чтения файла #{file_path}: #{e.message}"
      nil
    end
  end

  def generate_navigation_content(files_by_module, component_name)
    lines = []
    
    # Приоритетный порядок модулей для information-system
    module_order = case component_name
    when 'information-system'
      %w[ROOT trd oed ed pmi]
    when 'data-processing-engine'
      %w[ROOT hardware-complex user-guide program-description system-programmer-guide]
    else
      # Обычный порядок: ROOT первый, остальные по алфавиту
      modules = files_by_module.keys.sort
      modules.unshift(modules.delete('ROOT')) if modules.include?('ROOT')
      modules
    end
    
    # Собираем все файлы в правильном порядке
    ordered_files = {}
    module_order.each do |module_name|
      if files_by_module.key?(module_name)
        ordered_files[module_name] = files_by_module[module_name]
      end
    end
    
    # Добавляем остальные модули, которых нет в списке порядка
    files_by_module.each do |module_name, module_files|
      ordered_files[module_name] = module_files unless ordered_files.key?(module_name)
    end
    
    # Генерируем навигацию
    ordered_files.each_with_index do |(module_name, module_files), index|
      if module_name == 'ROOT'
        # Главная страница ROOT
        index_file = module_files.find { |f| f[:name] == 'index' }
        if index_file
          lines << "* xref:index.adoc[#{index_file[:title]}]"
        end
        
        # Остальные файлы ROOT
        module_files.reject { |f| f[:name] == 'index' }.each do |file|
          lines << "** xref:#{file[:name]}.adoc[#{file[:title]}]"
        end
      else
        # Файлы из модулей
        index_file = module_files.find { |f| f[:name] == 'index' }
        if index_file
          lines << "** xref:#{module_name}:index.adoc[#{index_file[:title]}]"
          
          # Подстраницы модуля
          module_files.reject { |f| f[:name] == 'index' }.each do |file|
            lines << "*** xref:#{module_name}:#{file[:name]}.adoc[#{file[:title]}]"
          end
        else
          # Нет index.adoc в модуле - все файлы как основные
          module_files.each do |file|
            lines << "** xref:#{module_name}:#{file[:name]}.adoc[#{file[:title]}]"
          end
        end
      end
    end
    
    lines.join("\n") + "\n"
  end

  def get_component_title(component_name)
    case component_name
    when 'information-system'
      'Информационная система'
    when 'data-processing-engine'
      'Центр обработки данных'
    when 'project-guide'
      'Обзор проекта ODS'
    else
      component_name.split('-').map(&:capitalize).join(' ')
    end
  end


  def update_nav_with_include(component_name)
    components_dir = File.dirname(@config_path).gsub('tools', 'components')
    nav_path = File.join(components_dir, component_name, 'modules', 'ROOT', 'nav.adoc')
    
    unless File.exist?(nav_path)
      puts "⚠️  nav.adoc не найден: #{nav_path}"
      return false
    end

    # Получаем настройки списков и вычисляем правильный путь include
    list_settings = get_list_settings_for_component(component_name)
    list_file_path = calculate_relative_include_path(nav_path, list_settings[:dst], component_name)
    
    nav_content = File.read(nav_path, encoding: 'UTF-8')
    
    # Проверяем, есть ли уже include с правильным путем
    if nav_content.include?("include::#{list_file_path}[]")
      # puts "✅ include уже есть в #{nav_path}"
      return true
    end
    
    # Удаляем старые include если есть
    nav_content = nav_content.gsub(/include::.*list-pages-component\.adoc\[\]\n/, '')
    
    # Добавляем include в конец файла
    nav_content += "\n\n// Автоматически сгенерированная навигация\n"
    nav_content += "include::#{list_file_path}[]\n"
    
    File.write(nav_path, nav_content, encoding: 'UTF-8')
    # puts "✅ Добавлен include в #{nav_path}: #{list_file_path}"
    true
  end

  private

  def get_list_settings_for_component(component_name)
    # Читаем config.yml для получения настроек
    require_relative 'config_parser'
    config = ConfigParser.load_config(@config_path)
    defaults = config['defaults']
    all_components = config['components']
    
    # Передаем имя компонента, defaults и все компоненты для объединения настроек
    ConfigParser.get_list_settings(component_name, {'defaults' => defaults}, all_components)
  end

  def calculate_relative_include_path(nav_path, dst_path, component_name)
    # Расширяем dst_path с помощью переменной {name}
    expanded_dst = dst_path.gsub('{name}', component_name)
    
    # nav_path: /path/to/components/component/modules/ROOT/nav.adoc
    # ROOT dir: /path/to/components/component/modules/ROOT/
    # dst:      /path/to/components/component/modules/ROOT/partials/lists
    # файл:     /path/to/components/component/modules/ROOT/partials/lists/list-pages-component.adoc
    
    # Упрощенный подход: извлекаем относительную часть от modules/ROOT
    # dst: "components/{name}/modules/ROOT/partials/lists"
    # nav: "components/{name}/modules/ROOT/nav.adoc"
    # путь: "partials/lists/list-pages-component.adoc"
    
    if expanded_dst.include?('modules/ROOT/')
      relative_part = expanded_dst.split('modules/ROOT/').last
      relative_path = File.join(relative_part, 'list-pages-component.adoc')
    else
      # Fallback на старый подход
      relative_path = 'partials/list-pages-component.adoc'
    end
    
    # puts "🔍 Вычисление пути:"
    # puts "  dst: #{expanded_dst}"
    # puts "  include:: #{relative_path}[]"

    relative_path
  end

  # Генерирует содержимое списка PDF файлов
  def generate_pdf_list_content(pdf_file, index)
    filename = File.basename(pdf_file, '.pdf')
    title = extract_pdf_title(pdf_file)
    
    # Формат: ". xref:attachment$filename.pdf[title]" (для ссылки на PDF в Antora)
    display_name = title && !title.empty? ? title : filename
    ". xref:attachment$#{filename}.pdf[#{display_name}]"
  end

  # Генерирует содержимое табличного списка PDF файлов
  def generate_pdf_table_content(pdf_files)
    lines = []
    
    pdf_files.each_with_index do |pdf_file, index|
      filename = File.basename(pdf_file, '.pdf')
      title = extract_pdf_title(pdf_file)
      page_count = extract_pdf_page_count(pdf_file)
      
      # Формат: "^| {counter:num-list-t} | xref:attachment$filename.pdf[title] | Листов: Количество"
      display_name = title && !title.empty? ? title : filename
      lines << "^| {counter:num-list-t} | xref:attachment$#{filename}.pdf[#{display_name}] | Листов: #{page_count}"
      # puts "📄 Обработан PDF для таблицы: #{filename} -> #{display_name} (#{page_count} листов)"
    end
    
    lines.empty? ? '' : lines.join("\n") + "\n"
  end

  # Извлекает название из имени PDF файла
  def extract_pdf_title(pdf_file)
    # Используем имя файла без расширения
    filename = File.basename(pdf_file, '.pdf')
    # Заменяем подчеркивания на пробелы для лучшего отображения
    filename.gsub('_', ' ')
  end

  # Извлекает количество страниц из PDF файла
  def extract_pdf_page_count(pdf_file)
    require 'hexapdf'
    
    doc = HexaPDF::Document.open(pdf_file)
    doc.pages.size
  rescue => e
    puts "⚠️  Ошибка чтения количества страниц PDF #{pdf_file}: #{e.message}"
    0
  end
end

# CLI интерфейс
if __FILE__ == $0
  generator = ListGenerator.new
  generator.generate_all_components
end
