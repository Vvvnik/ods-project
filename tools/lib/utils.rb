#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'pathname'

# Модуль с утилитарными функциями для работы с файловой системой и командами
# Содержит функции для запуска команд, работы с путями, создания директорий
# и других вспомогательных операций
# 
# Вызывается из: pdf_generator.rb и других модулей для файловых операций
# Используется для: выполнения команд, работы с путями, создания директорий
module Utils
  # Хелпер для запуска команды с выводом и проверкой статуса
  def self.run!(cmd)
    puts "Выполняется команда: #{cmd}"
    status = system(cmd)
    puts "\n"
    unless status
      puts "❌ Команда завершилась с ошибкой: #{cmd}"
      exit 1
    end
  end

  # Функция для расширения путей с подстановкой {name}
  def self.expand(str, comp)
    return str unless str.is_a?(String)
    str.gsub('{name}', comp['name'])
  end

  # Функция для добавления title в PDF
  def self.set_pdf_title(input_path, output_path, title)
    require 'hexapdf'
    
    doc = HexaPDF::Document.open(input_path)
    
    # Устанавливаем атрибут Title
    doc.trailer[:Info] ||= {}
    doc.trailer[:Info][:Title] = title
    
    # Сохраняем изменения
    doc.write(output_path, optimize: true)
    puts "Обработан файл: #{input_path}, Title: #{title}"
  rescue => e
    puts "⚠️  Ошибка при обработке PDF #{input_path}: #{e.message}"
    # Если не удалось обработать с hexapdf, просто копируем файл
    FileUtils.cp(input_path, output_path)
  end

  # Создание директории с очисткой если нужно
  def self.prepare_destination_dir(dst_dir, erase_folder = false)
    # Проверяем, существовала ли директория до создания
    dir_existed = Dir.exist?(dst_dir)
    
    FileUtils.mkdir_p(dst_dir)
    
    # Очищаем только если erase_folder = true И директория уже существовала
    if erase_folder && dir_existed
      puts "    🗑️  Очистка папки назначения: #{dst_dir}"
      FileUtils.rm_rf(Dir.glob("#{dst_dir}/*"))
    end
  end

  # Фильтрация файлов по списку исключений
  def self.filter_files(files, exclude_files)
    return files if exclude_files.empty?
    
    puts "    ⚠️ Исключаем файлы: #{exclude_files.join(', ')}"
    files.reject do |file|
      exclude_files.any? { |exclude| File.basename(file) == exclude }
    end
  end

  # Определение имени файла с учетом модуля
  def self.generate_file_name(adoc_file)
    base_name = File.basename(adoc_file, '.adoc')
    
    # Определяем модуль из пути для создания уникального имени
    path_parts = Pathname.new(adoc_file).each_filename.to_a
    module_index = path_parts.index('modules')
    if module_index && path_parts[module_index + 1]
      module_name = path_parts[module_index + 1]
      base_name = "#{module_name}_#{base_name}" unless module_name == 'ROOT'
    end
    
    base_name
  end
end
