#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'yaml'

class TranslationUtils
  def initialize(translations_file = 'tools/dictionary/database_translations.yml', log_file = 'tools/log/database_translations_log.txt')
    @translations_file = translations_file
    @log_file = log_file
    # Не очищаем лог автоматически - это должно быть явным действием
  end

  def add_translation(key, translation)
    return false if key.nil? || translation.nil? || translation.empty?

    # Постобработка перевода
    cleaned_translation = translation.strip
      .gsub(/\.$/, '')                    # Убираем точки в конце
      .gsub(/_/, ' ')                     # Заменяем подчеркивания на пробелы
      .gsub(/\s+/, ' ')                   # Убираем лишние пробелы
      .strip                               # Убираем пробелы в начале и конце

    # Исправляем слипшиеся слова (добавляем пробелы между заглавными буквами)
    cleaned_translation = cleaned_translation.gsub(/([а-я])([А-Я])/, '\1 \2')

    # Исправляем заглавную букву
    cleaned_translation = cleaned_translation.capitalize if cleaned_translation.length > 0

    # Читаем существующие переводы
    existing_translations = load_existing_translations

    # Проверяем, есть ли уже такой перевод
    if existing_translations[key.downcase] == cleaned_translation
      return false
    end

    # Добавляем новый перевод
    existing_translations[key.downcase] = cleaned_translation
    save_translations(existing_translations)
    log_new_translation(key, cleaned_translation)
    true
  end

  def log_new_translation(key, translation)
    timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
    log_entry = "#{timestamp} | #{key} → #{translation}\n"
    
    File.open(@log_file, 'a', encoding: 'utf-8') do |f|
      f.write(log_entry)
    end
  end

  def clear_log
    File.write(@log_file, "# Лог переводов LLM\n# Обновляется при каждом запуске\n\n", encoding: 'utf-8')
  end

  private

  def load_existing_translations
    return {} unless File.exist?(@translations_file)

    begin
      content = File.read(@translations_file, encoding: 'utf-8')
      yaml_data = YAML.load(content)
      translations = yaml_data['translations'] || {}
      
      # Конвертируем ключи в нижний регистр для поиска
      normalized_translations = {}
      translations.each do |key, value|
        normalized_translations[key.downcase] = value
      end
      
      normalized_translations
    rescue => e
      puts "⚠️  Ошибка загрузки словаря переводов: #{e.message}"
      {}
    end
  end

  def save_translations(translations)
    # Создаем структуру YAML
    yaml_data = {
      'translations' => translations
    }
    
    # Добавляем комментарий в начало
    yaml_content = "# Словарь переводов атрибутов базы данных\n# Формат: оригинальное_имя: \"перевод\"\n\n"
    yaml_content += YAML.dump(yaml_data)
    
    # Сохраняем файл
    File.write(@translations_file, yaml_content, encoding: 'utf-8')
  end
end