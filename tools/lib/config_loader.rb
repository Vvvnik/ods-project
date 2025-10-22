#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'

module ConfigLoader
  def self.load_config(config_path = 'tools/config.yml')
    config_file = File.expand_path(config_path)
    
    unless File.exist?(config_file)
      puts "⚠️  Файл конфигурации не найден: #{config_file}"
      return {}
    end
    
    begin
      config_content = File.read(config_file, encoding: 'utf-8')
      
      # Заменяем переменные окружения в YAML
      config_content = expand_env_vars(config_content)
      
      # Загружаем YAML с поддержкой алиасов
      config = YAML.load(config_content, aliases: true)
      
      # Находим компонент по имени
      component_name = extract_component_name_from_path
      component_config = find_component_config(config, component_name)
      
      component_config || {}
    rescue => e
      puts "❌ Ошибка загрузки конфигурации: #{e.message}"
      {}
    end
  end

  def self.load_config_for_component(component_name, config_path = 'tools/config.yml')
    config_file = File.expand_path(config_path)
    
    unless File.exist?(config_file)
      puts "⚠️  Файл конфигурации не найден: #{config_file}"
      return {}
    end
    
    begin
      config_content = File.read(config_file, encoding: 'utf-8')
      
      # Заменяем переменные окружения в YAML
      config_content = expand_env_vars(config_content)
      
      # Загружаем YAML с поддержкой алиасов
      config = YAML.load(config_content, aliases: true)
      
      # Находим компонент по имени
      component_config = find_component_config(config, component_name)
      
      component_config || {}
    rescue => e
      puts "❌ Ошибка загрузки конфигурации: #{e.message}"
      {}
    end
  end
  
  private
  
  def self.expand_env_vars(content)
    # Заменяем ${VAR:-default} на значения переменных окружения
    content.gsub(/\$\{([^:}]+):-([^}]+)\}/) do |match|
      var_name = $1
      default_value = $2
      ENV[var_name] || default_value
    end
  end
  
  def self.extract_component_name_from_path
    # Извлекаем имя компонента из текущего пути выполнения
    # Например: components/airport-service/modules/ROOT/partials/docs-db
    current_dir = Dir.pwd
    
    if current_dir.include?('components/')
      parts = current_dir.split('/')
      components_index = parts.index('components')
      if components_index && parts[components_index + 1]
        return parts[components_index + 1]
      end
    end
    
    # Fallback: пытаемся определить по аргументам командной строки
    ARGV.each_with_index do |arg, index|
      if arg == '--out' && ARGV[index + 1]
        out_path = ARGV[index + 1]
        # Обрабатываем как абсолютные, так и относительные пути
        if out_path.include?('components/')
          parts = out_path.split('/')
          components_index = parts.index('components')
          if components_index && parts[components_index + 1]
            return parts[components_index + 1]
          end
        end
      end
    end
    
    # Если не удалось определить, возвращаем airport-service по умолчанию
    'airport-service'
  end
  
  def self.find_component_config(config, component_name)
    return {} unless config.is_a?(Hash)
    
    components = config['components']
    return {} unless components.is_a?(Array)
    
    component = components.find { |c| c['name'] == component_name }
    return {} unless component.is_a?(Hash)
    
    # Применяем defaults если есть
    defaults = config['defaults']
    if defaults.is_a?(Hash)
      # Создаем копию defaults и мержим с конфигурацией компонента
      merged_config = defaults.dup
      
      # Рекурсивно мержим конфигурацию компонента
      component.each do |key, value|
        if merged_config[key].is_a?(Hash) && value.is_a?(Hash)
          merged_config[key] = merged_config[key].merge(value)
        else
          merged_config[key] = value
        end
      end
      
      merged_config
    else
      component
    end
  end
end