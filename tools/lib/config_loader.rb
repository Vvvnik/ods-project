# Модуль для загрузки конфигурации
# Предоставляет общий метод load_config для всех конвертеров
module ConfigLoader
  
  def load_config
    config_path = File.join(File.dirname(__FILE__), '..', 'config_type_page.yml')
    if File.exist?(config_path)
      YAML.load_file(config_path)
    else
      {}
    end
  rescue => e
    puts "Ошибка загрузки конфигурации: #{e.message}"
    {}
  end
  
end
