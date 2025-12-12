#!/usr/bin/env ruby
# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'
require_relative 'translation_utils'
require_relative 'prompt_loader'

class LLMClient
  def initialize(host = 'http://localhost:11434', model = 'qwen2.5:latest', prompts_dir = nil, prompt_template = 'database_translations')
    @host = host
    @model = model
    @uri = URI("#{host}/api/generate")
    @translation_utils = TranslationUtils.new
    @prompt_loader = PromptLoader.new(prompts_dir, prompt_template)
  end

  def translate_attribute_name(attribute_name)
    return attribute_name if attribute_name.nil? || attribute_name.empty?

    # Проверяем, не на русском ли уже имя атрибута
    return attribute_name if russian_text?(attribute_name)

    # Используем пакетный промпт для одного поля
    translations = translate_batch([attribute_name], "ru")
    return translations[attribute_name] if translations[attribute_name]

    # Fallback: если LLM не ответил или ответил пустым, используем простую конвертацию
    fallback = create_fallback_translation(attribute_name)
    puts "⚠️  LLM не ответил, используем fallback: '#{fallback}'"
    @translation_utils.add_translation(attribute_name, fallback)
    fallback
  end

  def translate_to_english(text)
    return text if text.nil? || text.empty?

    # Используем пакетный промпт для одного поля
    translations = translate_batch([text], "en")
    return translations[text] if translations[text]

    # Fallback: возвращаем оригинальный текст
    text
  end

  def translate_batch(fields, translate_comments)
    return {} if fields.nil? || fields.empty?

    begin
      # Определяем язык перевода
      target_language = case translate_comments
                      when "ru", true then "русский"
                      when "en" then "английский"
                      else "английский"
                      end

      # Загружаем промпт для пакетного перевода
      prompt = @prompt_loader.load_prompt('database_translations', {
        fields: fields,
        target_language: target_language
      })

      puts "🤖 Отправляем пакет из #{fields.length} полей в LLM..."
      response = make_request(prompt)
      
      if response && !response.empty?
        translations = parse_batch_response(response, fields)
        puts "✅ Получено #{translations.length} переводов из #{fields.length} полей"
        return translations
      end
    rescue => e
      puts "⚠️  Ошибка пакетного перевода: #{e.message}"
    end

    # fallback - переводим по одному
    puts "⚠️  Fallback к индивидуальному переводу..."
    translations = {}
    fields.each do |field|
      if translate_comments == "en"
        translations[field] = translate_to_english(field)
      else
        translations[field] = translate_attribute_name(field)
      end
    end
    translations
  end

  private


  def parse_batch_response(response, fields)
    translations = {}
    
    # Очищаем ответ
    cleaned_response = clean_llm_response(response)
    
    # LLM может вернуть все в одной строке, разделяем по номеру
    # Ищем паттерн "число. поле → перевод"
    pattern = /(\d+)\.\s*([^→]+?)\s*→\s*([^0-9]+?)(?=\s*\d+\.|$)/
    
    cleaned_response.scan(pattern) do |match|
      number = match[0]
      field_name = match[1].strip
      translation = match[2].strip
      
      # Находим оригинальное поле (может быть с разными регистрами и пробелами вместо подчеркиваний)
      original_field = fields.find { |f| 
        f.downcase == field_name.downcase || 
        f.downcase.gsub('_', ' ') == field_name.downcase ||
        field_name.downcase.gsub(' ', '_') == f.downcase
      }
      
      if original_field && !is_bad_translation?(translation)
        translations[original_field] = translation
      end
    end
    
    # Если не удалось распарсить - пробуем разбить по строкам
    if translations.empty?
      puts "⚠️ Пробуем разбить по строкам..."
      lines = cleaned_response.split("\n")
      
      lines.each do |line|
        line = line.strip
        next if line.empty?
        
        # Ищем строки вида "1. field_name → translation"
        if line.match(/^\d+\.\s+(.+?)\s*→\s*(.+)$/)
          field_name = $1.strip
          translation = $2.strip
          
          original_field = fields.find { |f| 
            f.downcase == field_name.downcase || 
            f.downcase.gsub('_', ' ') == field_name.downcase ||
            field_name.downcase.gsub(' ', '_') == f.downcase
          }
          
          if original_field && !is_bad_translation?(translation)
            translations[original_field] = translation
          end
        end
      end
    end
    
    translations
  end

  def make_request(prompt)
    request_body = {
      model: @model,
      prompt: prompt,
      stream: false,
      options: {
        temperature: 0.1,
        top_p: 0.9
      }
    }

    http = Net::HTTP.new(@uri.host, @uri.port)
    http.read_timeout = 30
    http.open_timeout = 10

    request = Net::HTTP::Post.new(@uri)
    request['Content-Type'] = 'application/json'
    request.body = request_body.to_json

    response = http.request(request)
    
    if response.code == '200'
      result = JSON.parse(response.body)
      translated = result['response']&.strip
      
      # Постобработка
      translated = translated.gsub(/^["']|["']$/, '') # убираем кавычки
      translated = translated.gsub(/\.$/, '') # убираем точки в конце
      # Не применяем capitalize - переводы должны приходить уже правильно отформатированными
      
      translated
    else
      puts "❌ Ошибка LLM API: #{response.code} #{response.message}"
      nil
    end
  end

  def russian_text?(text)
    # Простая проверка на русский текст
    text.match?(/[а-яё]/i)
  end

  def clean_llm_response(response)
    cleaned = response.strip
      .gsub(/^["']|["']$/, '')  # убираем кавычки
      .gsub(/\.$/, '')          # убираем точки в конце
      .gsub(/_/, ' ')           # заменяем подчеркивания на пробелы
      .gsub(/\s+/, ' ')         # убираем лишние пробелы
      .strip                    # убираем пробелы в начале и конце
    
    # Убираем префиксы типа "Ответ:", "Перевод:", "Answer:" и т.д.
    cleaned = cleaned.gsub(/^(ответ|перевод|answer|translation):\s*/i, '')
    
    # Убираем постфиксы типа " - это перевод" и т.д.
    cleaned = cleaned.gsub(/\s*-\s*(это|is)\s*(перевод|translation).*$/i, '')
    
    # Не применяем capitalize - переводы должны приходить уже правильно отформатированными
    cleaned
  end

  def is_bad_translation?(translation)
    return true if translation.length < 3
    
    bad_patterns = [
      'атрибут', 'таблицы', 'базы', 'данных', 'имя', 'перевод',
      'attribute', 'field', 'name', 'table', 'database', 'translation',
      'answer:', 'ответ:', 'перевод:', 'translation:', 'translation is',
      'i\'m not sure', 'не уверен', 'could you please', 'please provide',
      'пожалуйста', 'provide the', 'дайте', 'укажите', 'введите',
      'the translation', 'перевод будет', 'это переводится как',
      'field name', 'имя поля', 'database field', 'поле базы данных'
    ]
    
    bad_patterns.any? { |pattern| translation.downcase.include?(pattern) }
  end

  def create_fallback_translation(attribute_name)
    attribute_name.gsub(/_/, ' ')
  end
end
