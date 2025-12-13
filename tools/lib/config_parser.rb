#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require_relative 'utils'

# Модуль для парсинга и обработки конфигурационных файлов проекта
# Содержит функции для загрузки YAML конфигурации, получения настроек PDF,
# обработки компонентов и их параметров
# 
# Вызывается из: pdf_generator.rb и других модулей для получения настроек
# Используется для: чтения конфигурации из tools/config.yml и обработки параметров
module ConfigParser
  # Загрузка конфигурации из файла
  def self.load_config(config_path = 'tools/config.yml')
    YAML.safe_load(File.read(config_path), aliases: true)
  end

  # Получение значения с fallback на defaults
  def self.get_value(comp, key, defaults)
    comp[key] || defaults.dig('defaults', key) || nil
  end

  # Получение настроек PDF для компонента
  def self.get_pdf_settings(comp, defaults)
    pdf_config = comp['pdf'] || defaults.dig('defaults', 'pdf') || {}
    
    {
      converter: pdf_config['converter'] || 'tools/scripts/convert_ascii_to_pdf.rb',
      theme: pdf_config['theme'] || 'report',
      themes_dir: pdf_config['themes_dir'] || 'resources/themes',
      fonts_dir: pdf_config['fonts_dir'] || 'resources/fonts',
      enabled: pdf_config['enabled'] || false,
      src: Utils.expand(pdf_config['src'] || defaults.dig('defaults', 'pdf', 'src'), comp),
      dst: Utils.expand(pdf_config['dst'] || defaults.dig('defaults', 'pdf', 'dst'), comp),
      erase_folder: pdf_config['erase_destination_folder'] || defaults.dig('defaults', 'pdf', 'erase_destination_folder') || false,
      exclude_files: pdf_config['exclude_files'] || defaults.dig('defaults', 'pdf', 'exclude_files') || [],
      use_title_pages: pdf_config['use_title_pages'] || defaults.dig('defaults', 'pdf', 'use_title_pages') || false,
      generate_specification: pdf_config['generate_specification'] != nil ? pdf_config['generate_specification'] : (defaults.dig('defaults', 'pdf', 'generate_specification') != nil ? defaults.dig('defaults', 'pdf', 'generate_specification') : true)
    }
  end

  # Получение настроек БД для компонента
  def self.get_db_settings(comp, defaults, name)
    db_settings = comp['db'] || defaults.dig('defaults', 'db') || {}
    db_config_path = Utils.expand(db_settings['database_connect_file'] || defaults.dig('defaults', 'db', 'database_connect_file'), comp)
    return nil unless File.exist?(db_config_path)
    
    db_config = YAML.safe_load(File.read(db_config_path))
    default_profile = db_config['default_profile'] || 'pg_demo'
    prof = db_config['profiles'][default_profile] || {}
    
    # ENV-переменные могут переопределить профиль
    prof['host'] = ENV['DB_HOST'] if ENV['DB_HOST']
    prof['port'] = ENV['DB_PORT'] if ENV['DB_PORT']
    prof['db']   = ENV['DB_NAME'] if ENV['DB_NAME']
    prof['user'] = ENV['DB_USER'] if ENV['DB_USER']
    prof['pass'] = ENV['DB_PASS'] if ENV['DB_PASS']

    db_settings = comp['db'] || defaults.dig('defaults', 'db') || {}

    {
      enabled: db_settings['enabled'] || false,
      profile: default_profile,
      connection: prof,
      dst: Utils.expand(db_settings['dst'] || defaults.dig('defaults', 'db', 'dst'), comp),
      images_dir: Utils.expand(db_settings['images_dir'] || defaults.dig('defaults', 'db', 'images_dir'), comp),
      erase_folder: db_settings['erase_destination_folder'] || defaults.dig('defaults', 'db', 'erase_destination_folder') || false
    }
  end

  # Получение настроек API для компонента
  def self.get_api_settings(comp, defaults, name)
    api_settings = comp['api'] || defaults.dig('defaults', 'api') || {}
    
    {
      enabled: api_settings['enabled'] || false,
      dst: Utils.expand(api_settings['dst'] || defaults.dig('defaults', 'api', 'dst'), comp),
      sources_file: Utils.expand(api_settings['api_sources_file'] || defaults.dig('defaults', 'api', 'api_sources_file'), comp),
      erase_folder: api_settings['erase_destination_folder'] || defaults.dig('defaults', 'api', 'erase_destination_folder') || false
    }
  end

  # Получение настроек диаграмм для компонента
  def self.get_diagram_settings(comp, defaults)
    bpmn_settings = comp['bpmn'] || defaults.dig('defaults', 'bpmn') || {}
    drawio_settings = comp['drawio'] || defaults.dig('defaults', 'drawio') || {}
    
    {
      bpmn_enabled: bpmn_settings['enabled'] || false,
      bpmn_src: Utils.expand(bpmn_settings['src'] || defaults.dig('defaults', 'bpmn', 'src'), comp),
      bpmn_dst: Utils.expand(bpmn_settings['dst'] || defaults.dig('defaults', 'bpmn', 'dst'), comp),
      bpmn_erase_folder: bpmn_settings['erase_destination_folder'] || defaults.dig('defaults', 'bpmn', 'erase_destination_folder') || false,
      drawio_enabled: drawio_settings['enabled'] || false,
      drawio_src: Utils.expand(drawio_settings['src'] || defaults.dig('defaults', 'drawio', 'src'), comp),
      drawio_dst: Utils.expand(drawio_settings['dst'] || defaults.dig('defaults', 'drawio', 'dst'), comp),
      drawio_erase_folder: drawio_settings['erase_destination_folder'] || defaults.dig('defaults', 'drawio', 'erase_destination_folder') || false
    }
  end

  # Получение настроек списков для компонента
  # Объединяет настройки из всех записей компонента с одинаковым именем
  def self.get_list_settings(comp_name, defaults, all_components)
    # Найти все записи для компонента
    component_entries = all_components.select { |comp| comp['name'] == comp_name }
    
    # Начать с настроек по умолчанию
    merged_list_settings = defaults.dig('defaults', 'list') || {}
    
    # Объединить настройки из всех записей компонента
    component_entries.each do |entry|
      if entry['list']
        merged_list_settings = merged_list_settings.merge(entry['list'])
      end
    end
    
    # Создать объект компонента для Utils.expand (нужен для подстановки {name})
    comp_obj = {'name' => comp_name}
    
    {
      enabled: merged_list_settings['enabled'] || false,
      adoc_lists: merged_list_settings['adoc_lists'] || false,
      pdf_lists: merged_list_settings['pdf_lists'] || false,
      adoc_src: Utils.expand(merged_list_settings['adoc_src'] || defaults.dig('defaults', 'list', 'adoc_src'), comp_obj),
      pdf_src: Utils.expand(merged_list_settings['pdf_src'] || defaults.dig('defaults', 'list', 'pdf_src'), comp_obj),
      dst: Utils.expand(merged_list_settings['dst'] || defaults.dig('defaults', 'list', 'dst'), comp_obj),
    }
  end
end
