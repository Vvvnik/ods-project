require 'prawn'
require 'asciidoctor-pdf'
require 'date'
require 'yaml'
require_relative '../lib/config_loader'
require_relative '../lib/convert_title_page_original'
require_relative '../lib/convert_title_page_contract'
require_relative '../lib/convert_title_page_original_frame'
require_relative '../lib/convert_approval_page_gost'
require_relative '../lib/convert_other_page_original'
require_relative '../lib/convert_other_page_original_frame'

class PDFConverterCustomTitlePage < (Asciidoctor::Converter.for 'pdf')
  include ConfigLoader
  include ConvertApprovalPageGost
  register_for 'pdf'
  
  def initialize(*args)
    super(*args)
    @config = ConfigLoader.load_config
  end

  def init_pdf(doc)
    super(doc)
    @custom_title_page = doc.attr('custom_title_page') || 'none'
    @use_title_pages = doc.attr('use_title_pages') != 'false'
    
    # Если custom_title_page = 'none', то автоматически отключаем титульные страницы
    @use_title_pages = false if @custom_title_page == 'none'
    
    # Загружаем нужные модули на основе конфигурации только если титульные страницы включены
    load_title_page_module if @use_title_pages
  end

  def convert_document(doc)
    # Инициализируем атрибуты если еще не инициализированы
    @custom_title_page = doc.attr('custom_title_page') || 'none' if @custom_title_page.nil?
    @use_title_pages = doc.attr('use_title_pages') != 'false' if @use_title_pages.nil?
    
    # Загружаем модуль если еще не загружен и титульные страницы включены
    load_title_page_module if @title_page_module.nil? && @use_title_pages
    
    
    # Если это специальная титульная страница, обрабатываем документ без стандартной титульной страницы
    if @title_page_module && @title_page_module != nil && @use_title_pages
      # Временно отключаем титульную страницу
      original_title_page = doc.attr('title-page')
      doc.set_attribute('title-page', '')
      
      # Обрабатываем документ без титульной страницы
      super(doc)
      
      # Восстанавливаем оригинальное значение
      if original_title_page
        doc.set_attribute('title-page', original_title_page)
      end
      
      # Переходим на первую страницу и перерисовываем её
      go_to_page(1)
      canvas do
        fill_color 'FFFFFF'
        fill_rectangle [0, 0], page_width, page_height
      end
      
      # Вызываем метод модуля титульной страницы
      if @title_page_module == ConvertTitlePageContract
        ink_title_page(doc)
      elsif @title_page_module == ConvertTitlePageOriginal
        ink_title_page(doc)
      elsif @title_page_module == ConvertTitlePageOriginalFrame
        ink_title_page(doc)
      elsif @title_page_module == ConvertApprovalPageGost
        generate_approval_page_gost(doc)
      end
      
      # Количество листов добавляется внутри модулей титульных страниц
    else
      # Для none используем стандартную титульную страницу Asciidoctor
      super(doc)
    end
    
    # Автоматическая генерация листа утверждения если нужно
    generate_approval_page_if_needed(doc)
  end
  
  # Переопределяем обработку секций для пропуска первого заголовка при кастомной титульной странице
  def convert_section(section)
    # Если это кастомная титульная страница и это первая секция (заголовок документа), пропускаем её
    if @title_page_module && @title_page_module != nil && section.level == 0 && section.index == 0
      return
    end
    
    # Иначе обрабатываем как обычно
    super(section)
  end
  
  def draw_page_count_on_title_page
    # Сохраняем текущую страницу
    current_page = page_number
    
    # Переходим на первую страницу
    go_to_page(1)
    
    canvas do
      font('Times', style: :normal) do
        # Получаем размеры страницы
        page_width = page.dimensions[2]  # Ширина страницы
        page_height = page.dimensions[3] # Высота страницы
        
        # Позиция для текста "Листов X"
        mesto_list_x = page_width / 2 - 30
        mesto_list_y = page_height / 2 - 50
        my_font_size = 12
        
        fill_color '333333'
        draw_text "Листов #{page_count}", at: [mesto_list_x, mesto_list_y], size: my_font_size
      end
    end
    
    # Возвращаемся на исходную страницу
    go_to_page(current_page)
  end
  
  private
  
  def load_title_page_module
    title_page_config = @config['title_pages'] || {}
    module_name = title_page_config[@custom_title_page]
    
    
    if @custom_title_page == 'none' || module_name.nil? || module_name == 'none'
      @title_page_module = nil
    elsif module_name
      begin
        module_class = Object.const_get("#{module_name.split('_').map(&:capitalize).join}")
        self.class.include(module_class)
        @title_page_module = module_class
      rescue NameError => e
        puts "Предупреждение: Модуль #{module_name} не найден для типа #{@custom_title_page}: #{e.message}"
        @title_page_module = nil
      end
    else
      @title_page_module = nil
    end
  end
  
end

# Класс для полных рамок страниц
class PDFConverterWithFullPageBorder < (Asciidoctor::Converter.for 'pdf')
  include ConfigLoader
  register_for 'pdf'

  def initialize(*args)
    super(*args)
    @config = ConfigLoader.load_config
  end

  def init_pdf(doc)
    super(doc)
    @custom_other_page = doc.attr('custom_other_page') || 'original'
    @use_title_pages = doc.attr('use_title_pages') != 'false'
    
    # Если custom_title_page = 'none', то автоматически отключаем титульные страницы
    custom_title_page = doc.attr('custom_title_page') || 'none'
    @use_title_pages = false if custom_title_page == 'none'
    
    # Загружаем нужные модули на основе конфигурации
    load_other_page_module
  end

  def convert_document(doc)
    super(doc)
    # Если нужно рисовать рамки на всех страницах
    if @custom_other_page != 'none'
      draw_page_all(doc)
    end
  end

  def start_new_page(options = {})
    super(options)
    # Рисуем рамку только если это не первая страница или если указано
    if should_draw_border(options)
      # Для original_frame не рисуем здесь, только в draw_page_all
      if @custom_other_page != 'original_frame'
        draw_full_page_border(nil)
      end
    end
  end

  private
  
  def load_other_page_module
    other_page_config = @config['other_pages'] || {}
    module_name = other_page_config[@custom_other_page]
    
    if module_name && module_name != 'none'
      begin
        module_class = Object.const_get("#{module_name.split('_').map(&:capitalize).join}")
        self.class.include(module_class)
        @other_page_module = module_class
      rescue NameError => e
        puts "Предупреждение: Модуль #{module_name} не найден для типа #{@custom_other_page}: #{e.message}"
        @other_page_module = nil
      end
    else
      @other_page_module = nil
    end
  end

  def should_draw_border(options)
    # Не рисуем рамки если титульные страницы отключены
    return false unless @use_title_pages
    
    # Рисуем рамку если это не первая страница (титульная) или если явно указано
    return false if page_number == 1
    return true if @custom_other_page == 'original_frame'
    false
  end

  def draw_page_all(doc)
    # Не рисуем рамки если титульные страницы отключены
    return unless @use_title_pages
    
    # Сохраняем текущую страницу
    current_page = page_number
    
    # Рисуем рамки на всех страницах кроме первой (титульной)
    (2..page_count).each do |page_num|
      go_to_page(page_num)
      draw_full_page_border(doc)
    end
    
    # Возвращаемся на исходную страницу
    go_to_page(current_page)
  end

  def draw_full_page_border(doc)
    # Вызываем метод модуля для рисования рамки только если конвертер найден
    if @other_page_module == ConvertOtherPageOriginalFrame && doc
      ink_other_page_original_frame(doc)
    elsif @other_page_module == ConvertOtherPageOriginal && doc
      ink_other_page_original(doc)
    # Если конвертер не найден - не рисуем рамку вообще
    end
  end

end

# Класс للمодуля ConvertListAlphabetic
class CustomPDFConverter < (Asciidoctor::Converter.for 'pdf')
  include ConfigLoader
  register_for 'pdf'
  
  def initialize(*args)
    super(*args)
    @config = ConfigLoader.load_config
    @list_converter_module = nil
  end
  
  def init_pdf(doc)
    super(doc)
    load_list_converter_module(doc)
  end
  
  private
  
  def load_list_converter_module(doc)
    # Получаем тип списка из атрибута документа
    custom_list_type = doc.attr('custom_list_type')
    return unless custom_list_type
    
    # Получаем конфигурацию типов списков
    list_types = @config['list_types'] || {}
    module_name = list_types[custom_list_type]
    return unless module_name
    
    # Загружаем соответствующий модуль
    case module_name
    when "convert_list_alphabetic"
      require_relative 'convert_list_alphabetic'
      @list_converter_module = ConvertListAlphabetic
    when "convert_list_dash"
      require_relative 'convert_list_dash'  
      @list_converter_module = ConvertListDash
    end
    
    # Включаем модуль в текущий класс
    if @list_converter_module
      self.class.include(@list_converter_module)
      puts "✅ Загружен модуль списков: #{module_name}"
    end
  end
  
  # Автоматическая генерация листа утверждения если нужно
  def generate_approval_page_if_needed(doc)
    approval_page_type = doc.attr('approval-page')
    return unless approval_page_type
    
    # Проверяем, что атрибут не равен false
    if approval_page_type.to_s.downcase == 'false'
      puts "⏭️  Атрибут :approval-page: false, пропускаем генерацию ЛУ"
      return
    end
    
    puts "🔄 Найден атрибут :approval-page: #{approval_page_type}, генерируем лист утверждения..."
    
    # Получаем путь к основному документу
    doc_path = doc.attr('docfile') || doc.attr('docname')
    return unless doc_path
    
    # Определяем директорию основного документа
    doc_dir = File.dirname(doc_path)
    doc_name = File.basename(doc_path, '.adoc')
    
    # Генерируем лист утверждения используя ApprovalPageGenerator
    begin
      require_relative '../lib/approval_page_generator'
      
      # Используем новый генератор с встроенным шаблоном
      success = ApprovalPageGenerator.generate_approval_page(doc, nil, doc_dir)
      
      if success
        puts "✅ Лист утверждения сгенерирован в генерации листа утверждения"
      else
        puts "❌ Ошибка при генерации листа утверждения"
      end
      
    rescue => e
      puts "❌ Ошибка при генерации листа утверждения: #{e.message}"
    end
  end
  
end
