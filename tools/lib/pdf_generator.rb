#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require_relative 'utils'

# Модуль для генерации PDF файлов из AsciiDoc документов
# Содержит функции для создания аргументов PDF, обработки конфигурации компонентов
# и генерации PDF с использованием Asciidoctor и кастомных конвертеров
# 
# Вызывается из: scripts/convert_ascii_to_pdf.rb и других скриптов конвертации
# Используется для: автоматической генерации PDF документов из AsciiDoc
module PdfGenerator
  # Извлекает атрибут pdf-theme из документа
  def self.extract_pdf_theme_from_document(adoc_file)
    return nil unless File.exist?(adoc_file)
    
    File.readlines(adoc_file, encoding: 'UTF-8').each do |line|
      line = line.strip
      if line.start_with?(':pdf-theme:')
        theme = line.sub(':pdf-theme:', '').strip
        return theme unless theme.empty?
      end
    end
    
    nil
  end

  # Извлекает атрибут custom_other_page из документа
  def self.extract_custom_other_page_from_document(adoc_file)
    return nil unless File.exist?(adoc_file)
    
    File.readlines(adoc_file, encoding: 'UTF-8').each do |line|
      line = line.strip
      if line.start_with?(':custom_other_page:')
        page_type = line.sub(':custom_other_page:', '').strip
        return page_type unless page_type.empty?
      end
    end
    
    nil
  end

  # Функция для создания PDF аргументов на основе конфигурации
  def self.build_pdf_args(comp, kroki_url, adoc_file, defaults)
    # Получаем настройки PDF из конфигурации компонента или используем defaults
    pdf_settings = ConfigParser.get_pdf_settings(comp, defaults)
    pdf_converter = pdf_settings[:converter]
    pdf_theme = pdf_settings[:theme]
    pdf_themes_dir = pdf_settings[:themes_dir]
    pdf_fonts_dir = pdf_settings[:fonts_dir]
    use_title_pages = pdf_settings[:use_title_pages]
    
    # Проверяем, есть ли атрибут pdf-theme в самом документе
    document_theme = extract_pdf_theme_from_document(adoc_file)
    if document_theme
      pdf_theme = document_theme
      puts "    🎨 Используется тема из документа: #{pdf_theme}"
    else
      # Если тема не указана в документе, определяем по типу страниц
      custom_other_page = extract_custom_other_page_from_document(adoc_file)
      if custom_other_page == 'contract'
        # Для контрактов используем act тему (номера страниц с первой страницы)
        pdf_theme = 'act'
        # puts "    🎨 Выбрана тема 'act' для контрактов: #{custom_other_page}"
      elsif custom_other_page && custom_other_page.end_with?('_frame')
        # Для типов с суффиксом "_frame" используем frame тему (меньше полей)
        pdf_theme = 'frame'
        # puts "    🎨 Выбрана тема 'frame' для типа страниц: #{custom_other_page}"
      else
        # Для всех остальных типов используем report тему (больше полей)
        pdf_theme = 'report'
        # puts "    🎨 Выбрана тема 'report' для типа страниц: #{custom_other_page || 'default'}"
      end
    end
    
    # Проверяем существование файла конвертера и используем абсолютный путь
    if pdf_converter && File.exist?(pdf_converter)
      pdf_converter = File.expand_path(pdf_converter)
    else
      pdf_converter = nil
    end
    
    args = [
      '-r', 'asciidoctor-kroki'
    ]
    
    # Добавляем конвертер только если он существует
    if pdf_converter
      args << '-r'
      args << pdf_converter
    end
    
    args += [
      '-a', 'kroki-default-format=png',
      '-a', "kroki-server-url=#{kroki_url}",
      '-a', "pdf-themesdir=#{pdf_themes_dir}",
      '-a', "pdf-fontsdir=#{pdf_fonts_dir}",
      '-a', 'allow-uri-read'
    ]
    
    # Добавляем тему если она указана
    if pdf_theme
      args += ['-a', "pdf-theme=#{pdf_theme}"]
    end
    
    # Управление титульными страницами
    if use_title_pages
      # Включаем титульные страницы (используем настройки из документа)
      args += ['-a', 'title-page']
    else
      # Полностью отключаем титульные страницы
      args += ['-a', '!title-page', '-a', 'use_title_pages=false', '-a', 'notitle', '-a', 'no-title-page']
    end
    
   
    args
  end

  # Генерация PDF для компонента
  def self.generate_pdfs(comp, kroki_url, defaults)
    pdf_settings = ConfigParser.get_pdf_settings(comp, defaults)
    
    return unless pdf_settings[:enabled]
    
    src_pattern = pdf_settings[:src]
    dst_dir = pdf_settings[:dst]
    
    puts "  -> pdf: #{src_pattern} -> #{dst_dir}"
    
    # Подготавливаем директорию назначения
    Utils.prepare_destination_dir(dst_dir, pdf_settings[:erase_folder])
    
    # Ищем все .adoc файлы по паттерну (поддерживаем wildcard)
    adoc_files = Dir.glob("#{src_pattern}/**/*.adoc")
    
    # Фильтруем исключенные файлы
    adoc_files = Utils.filter_files(adoc_files, pdf_settings[:exclude_files])
    
    if adoc_files.empty?
      puts "    ⚠️  Не найдено .adoc файлов по паттерну #{src_pattern}"
      return
    end
    
    puts "    PDF настройки: theme=#{pdf_settings[:theme]}, converter=#{pdf_settings[:converter]}, title_pages=#{pdf_settings[:use_title_pages]}"
    
    # Группируем файлы по pages/ папкам
    pages_groups = adoc_files.group_by { |f| File.dirname(f) }
    
    pages_groups.each do |pages_dir, files|
      puts "    📁 Обработка папки: #{pages_dir}"
      
      # Генерируем все PDF в этой папке
      files.each do |adoc_file|
        # puts "    Обработка: #{File.basename(adoc_file)}"
        
        # Создаем PDF аргументы для этого файла
        pdf_args = build_pdf_args(comp, kroki_url, adoc_file, defaults)
        
        # Команда генерации PDF
        pdf_cmd = [
          'asciidoctor-pdf',
          *pdf_args,
          adoc_file
        ].join(' ')
        
        Utils.run!(pdf_cmd)
        
        # Проверяем что PDF создан
        pdf_file = adoc_file.gsub('.adoc', '.pdf')
        if File.exist?(pdf_file)
          # puts "    ✅ PDF создан в pages/: #{pdf_file}"
        else
          puts "    ⚠️  PDF файл не создан: #{pdf_file}"
        end
      end
      
      # После обработки всей папки переносим все PDF в attachments/
      move_pages_to_attachments(pages_dir, dst_dir)
    end
    
    puts "    📁 Все PDF файлы перенесены в attachments/"
  end
  
  # Переносит все PDF файлы из одной pages/ папки в attachments/
  def self.move_pages_to_attachments(pages_dir, dst_dir)
    puts "    📦 Перенос PDF файлов из #{pages_dir} в attachments/"
    
    # Ищем PDF файлы в этой pages/ папке
    pdf_files = Dir.glob("#{pages_dir}/**/*.pdf")
    
    if pdf_files.empty?
      puts "    ⚠️  PDF файлы в #{pages_dir} не найдены"
      return
    end
    
    pdf_files.each do |pdf_file|
      # Для файлов ЛУ используем их текущее имя, для обычных PDF - генерируем имя
      if pdf_file.include?('_LU.pdf')
        base_name = File.basename(pdf_file, '.pdf')
      else
        base_name = Utils.generate_file_name(pdf_file.gsub('.pdf', '.adoc'))
      end
      dst_pdf = File.join(dst_dir, "#{base_name}.pdf")
      
      # Обрабатывает PDF (добавляет title из метаданных)
      Utils.set_pdf_title(pdf_file, dst_pdf, base_name)
      
      # Удаляем исходный PDF из pages/ после успешного переноса
      FileUtils.rm(pdf_file) if File.exist?(dst_pdf) && dst_pdf != pdf_file
      
      # puts "    📄 Перенесен: #{File.basename(pdf_file)} -> #{dst_pdf}"
    end
    
    puts "    ✅ Из #{pages_dir}: перенесено #{pdf_files.size} PDF файлов"
  end
end
