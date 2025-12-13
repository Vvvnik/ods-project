#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require_relative 'utils'
require_relative 'config_parser'

# Модуль для генерации таблицы спецификации из обработанных PDF документов
# Создает таблицу specification-table.adoc на основе атрибутов из .adoc файлов
# 
# Вызывается из: start.rb после генерации PDF
# Используется для: создания таблицы спецификации для каждого модуля компонента
module SpecificationGenerator
  # Извлечение атрибутов из AsciiDoc файла
  def self.extract_attributes(file_path)
    return {} unless File.exist?(file_path)
    File.foreach(file_path).with_object({}) do |line, attrs|
      attrs[$1.strip] = $2.strip if line =~ /^:([^:]+):\s*(.+)$/
    end
  end

  # Получение порядкового числительного на русском языке
  def self.ordinal_word_ru(n)
    return '' if n.nil? || n.to_i == 0
    
    units = {
      1 => 'первая', 2 => 'вторая', 3 => 'третья', 4 => 'четвертая', 5 => 'пятая',
      6 => 'шестая', 7 => 'седьмая', 8 => 'восьмая', 9 => 'девятая'
    }

    teens = {
      10 => 'десятая', 11 => 'одиннадцатая', 12 => 'двенадцатая', 13 => 'тринадцатая',
      14 => 'четырнадцатая', 15 => 'пятнадцатая', 16 => 'шестнадцатая',
      17 => 'семнадцатая', 18 => 'восемнадцатая', 19 => 'девятнадцатая'
    }

    tens_full = {
      20 => 'двадцатая', 30 => 'тридцатая', 40 => 'сороковая', 50 => 'пятидесятая'
    }

    num = n.to_i
    return units[num] if units[num]
    return teens[num] if teens[num]
    return tens_full[num] if tens_full[num]

    if num < 100
      t = (num / 10) * 10
      u = num % 10
      if tens_full[t] && units[u]
        base = tens_full[t].sub(/ая$/, 'ь')
        return "#{base} #{units[u]}"
      end
    end

    num.to_s
  end

  # Получение имени программы из файла или из index.adoc модуля
#   def self.get_program_name(adoc_file, module_index_path)
#     # Сначала пробуем из самого файла
#     attrs = extract_attributes(adoc_file)
#     name_prog = attrs['name-prog']&.strip || ''
#     return name_prog unless name_prog.empty?

#     # Если нет, пробуем из index.adoc модуля
#     if File.exist?(module_index_path)
#       index_attrs = extract_attributes(module_index_path)
#       return index_attrs['name-prog']&.strip || ''
#     end

#     ''
#   end

  # Извлечение code_contract из включаемого файла contract.adoc
  def self.extract_code_contract(adoc_file)
    # Сначала проверяем, определен ли code_contract в самом файле
    attrs = extract_attributes(adoc_file)
    return attrs['code_contract'] if attrs['code_contract']
    
    # Если нет, ищем в включаемом файле contract.adoc
    # Определяем путь к contract.adoc относительно текущего файла
    file_dir = File.dirname(adoc_file)
    contract_path = File.join(file_dir, '../../ROOT/partials/contract.adoc')
    contract_path = File.expand_path(contract_path)
    
    if File.exist?(contract_path)
      contract_attrs = extract_attributes(contract_path)
      return contract_attrs['code_contract'] if contract_attrs['code_contract']
    end
    
    # Если не нашли, возвращаем пустую строку
    ''
  end

  # Разрешение full_code из файла (подстановка значений вложенных атрибутов)
  def self.resolve_full_code(adoc_file)
    attrs = extract_attributes(adoc_file)
    full_code_attr = attrs['full_code'] || ''
    
    # Если full_code содержит атрибуты вида {code_contract}, нужно их разрешить
    if full_code_attr.include?('{')
      # Извлекаем code_contract (может быть в самом файле или в contract.adoc)
      code_contract = extract_code_contract(adoc_file)
      
      # Заменяем вложенные атрибуты на их значения
      resolved = full_code_attr.dup
      resolved.gsub!(/\{code_contract\}/, code_contract)
      resolved.gsub!(/\{code_document\}/, attrs['code_document'] || '')
      resolved.gsub!(/\{tom\}/, attrs['tom']&.strip || '')
      # Убираем лишние пробелы
      resolved = resolved.split(' ').reject(&:empty?).join(' ')
      return resolved
    end
    
    full_code_attr
  end

  # Добавление строки в таблицу спецификации
  def self.append_to_specification_table(adoc_file, module_index_path, table_path, is_approval: false)
    attrs = extract_attributes(adoc_file)
    # Разрешаем full_code из конкретного документа
    full_code = resolve_full_code(adoc_file)
    # tom берется только из самого файла, не из index.adoc модуля
    tom = attrs['tom']&.strip || ''
    name_doc = attrs['name_document_master'] || ''
    name_prog = attrs['name_document_slave'] || ''
    name_prog_main = attrs['name_component'] || ''
    name_document_main = attrs['name_document_main'] || ''

    # Если это лист утверждения
    if is_approval
      text_elements = [name_doc, "Лист утверждения"].compact.reject(&:empty?)
      # Используем разрешенное значение full_code
      code_part = "#{full_code}-ЛУ"
      text_elements.each_with_index do |element, index|
        if index == 0
          row = "| #{code_part} | #{element} |"
        else
          # Для выравнивания используем пробелы по длине code_part
          row = "| #{' ' * code_part.length} | #{element} |"
        end
        File.open(table_path, 'a') { |f| f.puts row }
      end
      File.open(table_path, 'a') { |f| f.puts "| {nbsp} |  |" }
      return
    end

    # Исключаемые ключевые слова для определения показа части
    excluded_keywords = %w[specification спецификация statement ведомость]
    show_part = name_prog != name_prog_main &&
                !tom.to_s.strip.empty? &&
                !excluded_keywords.any? { |w| name_doc.to_s.downcase.include?(w) }
    tom_phrase = "Часть #{ordinal_word_ru(tom.to_i)}" if show_part
    name_prog = '' if name_prog == name_prog_main

    # Для спецификации используем только код (первая часть full_code)
    is_specification = name_doc.to_s.downcase.include?('спецификация') || name_doc.to_s.downcase.include?('specification')
    
    if is_specification
      # Для спецификации используем только первую часть full_code (code_contract)
      code_part = full_code.split(' ').first || full_code
    else
      # Для остальных документов используем полный разрешенный full_code
      code_part = full_code
    end

    # Формирование текстовых элементов
    text_elements = [name_doc, tom_phrase, name_prog_main].compact.reject(&:empty?)

    # Добавление строк в таблицу
    text_elements.each_with_index do |element, index|
      if index == 0
        row = "| #{code_part} | #{element} |"
      else
        # Для выравнивания используем пробелы по длине code_part
        row = "| #{' ' * code_part.length} | #{element} |"
      end
      File.open(table_path, 'a') { |f| f.puts row }
    end
    
    # Для спецификации добавляем дополнительную строку с name_document_main
    if is_specification && !name_document_main.to_s.strip.empty?
      row = "| #{' ' * code_part.length} | #{name_document_main} |"
      File.open(table_path, 'a') { |f| f.puts row }
    end
    
    File.open(table_path, 'a') { |f| f.puts "| {nbsp} |  |" }
  end

  # Добавление строки в таблицу ведомости
  def self.append_to_statement_table(adoc_file, module_index_path, table_path)
    attrs = extract_attributes(adoc_file)
    name_doc = attrs['name_document_master'] || ''
    filename = File.basename(adoc_file, '.adoc').downcase
    
    # Пропускаем спецификацию - она не должна быть в ведомости
    if name_doc.downcase.include?('спецификация') || name_doc.downcase.include?('specification') ||
       filename.include?('спецификация') || filename.include?('specification')
      return
    end
    
    # Разрешаем full_code из конкретного документа
    full_code = resolve_full_code(adoc_file)
    tom = attrs['tom']&.strip || ''
    name_prog = attrs['name_document_slave'] || ''
    name_prog_main = attrs['name_component'] || ''
    folder_number = attrs['folder_number'] || 'Папка №1'
    # Исключаемые ключевые слова для определения показа части
    excluded_keywords = %w[specification спецификация statement ведомость]
    show_part = name_prog != name_prog_main &&
                !tom.to_s.strip.empty? &&
                !excluded_keywords.any? { |w| name_doc.to_s.downcase.include?(w) }
    tom_phrase = "Часть #{ordinal_word_ru(tom.to_i)}" if show_part
    name_prog = '' if name_prog == name_prog_main

    # Используем разрешенное значение full_code из конкретного документа
    code_part = full_code

    # Формирование текстовой части
    text_part = [name_doc, tom_phrase, name_prog].compact.reject(&:empty?).join(" +\n")

    # Добавляем только для определенных номеров документов (20, 30, 32, 34)
    # return unless %w[20 13 35 90 30 32 34].include?(number_doc)

    row = "| #{code_part} | #{text_part} ^| 1 | #{folder_number} |{nbsp}  |  |  |"
    File.open(table_path, 'a') { |f| f.puts row }
  end

  # Определение типа таблицы по названию файла
  def self.determine_table_type(filename)
    filename_lower = filename.downcase
    if filename_lower.include?('specification') || filename_lower.include?('спецификация')
      :specification
    elsif filename_lower.include?('statement') || filename_lower.include?('ведомость')
      :statement
    else
      nil
    end
  end

  # Проверка наличия документа спецификации или ведомости
  def self.has_specification_document(adoc_files)
    adoc_files.any? do |adoc_file|
      attrs = extract_attributes(adoc_file)
      name_doc = attrs['name_document_master'] || ''
      filename = File.basename(adoc_file, '.adoc').downcase
      name_doc.downcase.include?('спецификация') || 
      name_doc.downcase.include?('specification') ||
      filename.include?('спецификация') ||
      filename.include?('specification')
    end
  end

  def self.has_statement_document(adoc_files)
    adoc_files.any? do |adoc_file|
      attrs = extract_attributes(adoc_file)
      name_doc = attrs['name_document_master'] || ''
      filename = File.basename(adoc_file, '.adoc').downcase
      name_doc.downcase.include?('ведомость') || 
      name_doc.downcase.include?('statement') ||
      filename.include?('ведомость') ||
      filename.include?('statement')
    end
  end

  # Генерация спецификации для модуля компонента
  def self.generate_specification(comp, module_name, pdf_settings)
    return unless pdf_settings[:enabled]

    comp_name = comp['name']
    pages_dir = File.join('components', comp_name, 'modules', module_name, 'pages')
    return unless Dir.exist?(pages_dir)

    # Путь к index.adoc модуля для получения общих атрибутов
    module_index_path = File.join(pages_dir, 'index.adoc')

    # Путь к таблицам
    tables_dir = File.join('components', comp_name, 'modules', module_name, 'partials', 'tables')
    spec_table_path = File.join(tables_dir, 'specification-table.adoc')
    statement_table_path = File.join(tables_dir, 'statement-table.adoc')

    # Находим все .adoc файлы в pages/, исключая index.adoc
    adoc_files = Dir.glob(File.join(pages_dir, '*.adoc')).reject do |f|
      File.basename(f) == 'index.adoc'
    end.sort

    if adoc_files.empty?
      puts "    ⚠️  Не найдено .adoc файлов для генерации таблиц в #{pages_dir}"
      return
    end

    # Проверяем наличие документов спецификации и ведомости
    has_spec = has_specification_document(adoc_files)
    has_stmt = has_statement_document(adoc_files)

    # Если нет ни спецификации, ни ведомости, выходим
    unless has_spec || has_stmt
      puts "    ⚠️  Не найдено документов спецификации или ведомости в модуле #{module_name}"
      return
    end

    # Создаем директорию для таблиц только если нужно
    FileUtils.mkdir_p(tables_dir) if has_spec || has_stmt

    # Очищаем таблицы если нужно
    File.delete(spec_table_path) if File.exist?(spec_table_path) && has_spec
    File.delete(statement_table_path) if File.exist?(statement_table_path) && has_stmt

    puts "    📋 Генерация таблиц для модуля #{module_name} (#{adoc_files.size} файлов)"
    puts "      - Спецификация: #{has_spec ? 'да' : 'нет'}"
    puts "      - Ведомость: #{has_stmt ? 'да' : 'нет'}"

    # Сортируем файлы: спецификация и ведомость должны быть первыми
    sorted_files = adoc_files.sort_by do |adoc_file|
      attrs = extract_attributes(adoc_file)
      name_doc = attrs['name_document_master'] || ''
      filename = File.basename(adoc_file, '.adoc').downcase
      
      # Приоритет: спецификация = 0, ведомость = 1, остальные = 2
      if name_doc.downcase.include?('спецификация') || name_doc.downcase.include?('specification') ||
         filename.include?('спецификация') || filename.include?('specification')
        0
      elsif name_doc.downcase.include?('ведомость') || name_doc.downcase.include?('statement') ||
            filename.include?('ведомость') || filename.include?('statement')
        1
      else
        2
      end
    end

    # Обрабатываем каждый файл в отсортированном порядке
    sorted_files.each do |adoc_file|
      attrs = extract_attributes(adoc_file)
      
      # В спецификацию добавляем ВСЕ файлы только если есть документ спецификации
      if has_spec
        append_to_specification_table(adoc_file, module_index_path, spec_table_path, is_approval: false)

        # Если есть лист утверждения (LU), добавляем его тоже
        should_add_approval = false
        
        if attrs['approval-page'] == 'true' || attrs['approval-page'] == true
          should_add_approval = true
        elsif attrs['tom'].nil? || attrs['tom'].strip.empty? || attrs['tom'] == '01'
          should_add_approval = true
        elsif attrs['code_document'] == '12' && attrs['tom'] == '02'
          should_add_approval = true
        end
        
        if should_add_approval
          # Добавляем лист утверждения в спецификацию
          append_to_specification_table(adoc_file, module_index_path, spec_table_path, is_approval: true)
        end
      end
      
      # В ведомость добавляем все файлы только если есть документ ведомости
      if has_stmt
        append_to_statement_table(adoc_file, module_index_path, statement_table_path)
      end
    end

    # Выводим информацию о созданных таблицах
    if has_spec && File.exist?(spec_table_path)
      puts "    ✅ Таблица спецификации создана: #{spec_table_path}"
    end
    if has_stmt && File.exist?(statement_table_path)
      puts "    ✅ Таблица ведомости создана: #{statement_table_path}"
    end
  end

  # Генерация спецификации для компонента (для всех модулей)
  def self.generate_for_component(comp, defaults)
    pdf_settings = ConfigParser.get_pdf_settings(comp, defaults)
    return unless pdf_settings[:enabled]

    comp_name = comp['name']
    modules_dir = File.join('components', comp_name, 'modules')
    return unless Dir.exist?(modules_dir)

    # Находим все модули в компоненте
    modules = Dir.glob(File.join(modules_dir, '*'))
                .select { |f| File.directory?(f) }
                .map { |f| File.basename(f) }

    modules.each do |module_name|
      generate_specification(comp, module_name, pdf_settings)
    end
  end
end

