require 'date'

# Базовый модуль для универсальных блоков титульной страницы
# Предоставляет общую функциональность для всех блоков
#
# ГИБРИДНАЯ СИСТЕМА ПОЗИЦИОНИРОВАНИЯ:
# Поддерживает два формата координат:
#
# 1. ОТНОСИТЕЛЬНЫЕ КООРДИНАТЫ (дроби от размеров страницы):
# - left_position: '1/3'   (1/3 от ширины страницы слева)
# - top_position: '1/10'   (1/10 от высоты страницы сверху)
# - width_ratio: '1/3'     (1/3 от ширины страницы)
# - height_ratio: '1/8'    (1/8 от высоты страницы)
#
# 2. АБСОЛЮТНЫЕ КООРДИНАТЫ (в сантиметрах):
# - left_position: 10.5    (10.5 см от левого края)
# - top_position: 2.0       (2.0 см от верхнего края)
# - width: 8.0              (8.0 см ширина)
# - height: 3.0             (3.0 см высота)
#
# ГИБРИДНАЯ СИСТЕМА ИНТЕРВАЛОВ:
# - custom_line_spacing: 0.7    (0.7 см интервал между строками)
# - custom_line_spacing: 20     (20 пикселей интервал между строками)
# - custom_line_spacing: '1/20'  (1/20 от высоты страницы)
#
module TitlePageBlocks
  # Константы для преобразования единиц измерения
  CM_TO_POINTS = 28.35  # 1 см = 28.35 точек
  MM_TO_POINTS = 2.835  # 1 мм = 2.835 точек
  
  # Базовый класс для всех блоков титульной страницы
  class BaseBlock
    attr_reader :x, :y, :width, :height, :page_width, :page_height
    
    def initialize(page_width, page_height, **options)
      @page_width = page_width
      @page_height = page_height
      
      # Парсим координаты (относительные или абсолютные)
      parse_position(options)
    end
    
    # Парсит дробные значения типа "1/3", "2/5" и т.д.
    def parse_fraction(fraction_string)
      return 0.0 if fraction_string.nil? || fraction_string.empty?
      
      if fraction_string.is_a?(String) && fraction_string.include?('/')
        numerator, denominator = fraction_string.split('/').map(&:to_f)
        denominator.zero? ? 0.0 : numerator / denominator
      elsif fraction_string.is_a?(Numeric)
        fraction_string.to_f
      else
        0.0
      end
    end
    
    # Определяет тип координат (относительные или абсолютные)
    def is_relative_coordinate?(value)
      return false if value.nil?
      
      if value.is_a?(String)
        # Если строка содержит '/', это относительные координаты
        value.include?('/')
      else
        # Если число, это абсолютные координаты
        false
      end
    end
    
    # Парсит интервал между строками (гибридная система)
    def parse_line_spacing(value)
      return 25.0 if value.nil?  # Значение по умолчанию
      
      if value.is_a?(String)
        # Если строка содержит '/', это относительные координаты
        if value.include?('/')
          parse_fraction(value) * @page_height
        else
          # Если строка без '/', это пиксели
          value.to_f
        end
      else
        # Если число меньше 10, считаем это сантиметрами
        # Если число больше 10, считаем это пикселями
        if value < 10.0
          value * CM_TO_POINTS  # Конвертируем см в пиксели
        else
          value  # Уже в пикселях
        end
      end
    end
    
    # Парсит позиции и размеры (гибридная система)
    def parse_position(options)
      # Позиция блока
      if is_relative_coordinate?(options[:left_position])
        # Относительные координаты
        left_ratio = parse_fraction(options[:left_position])
        top_ratio = parse_fraction(options[:top_position])
        width_ratio = parse_fraction(options[:width_ratio])
        height_ratio = parse_fraction(options[:height_ratio])
        
        # Вычисляем абсолютные координаты из относительных
        @x = (left_ratio * @page_width).round(2)
        @y = (@page_height - (top_ratio * @page_height)).round(2)  # Y идет сверху вниз
        @width = (width_ratio * @page_width).round(2)
        @height = (height_ratio * @page_height).round(2)
      else
        # Абсолютные координаты (в сантиметрах)
        @x = (options[:left_position] || 0) * CM_TO_POINTS
        @y = @page_height - ((options[:top_position] || 0) * CM_TO_POINTS)
        @width = (options[:width] || 0) * CM_TO_POINTS
        @height = (options[:height] || 0) * CM_TO_POINTS
      end
      
      # Значения по умолчанию если не заданы
      @x = 50 if @x.zero?
      @y = @page_height - 50 if @y == @page_height
      @width = @page_width - 100 if @width.zero?
      @height = 20 if @height.zero?
    end
    
    # Вычисляет позицию относительно размеров страницы
    def calculate_position(horizontal: :left, vertical: :top, margin: 50)
      case horizontal
      when :left
        @x = margin
      when :center
        @x = (@page_width - @width) / 2
      when :right
        @x = @page_width - @width - margin
      end
      
      case vertical
      when :top
        @y = @page_height - margin
      when :center
        @y = (@page_height - @height) / 2
      when :bottom
        @y = margin
      end
    end
    
    # Возвращает верхнюю границу блока
    def top_edge
      @y
    end
    
    # Возвращает правую границу блока
    def right_edge
      @x + @width
    end
    
    # Возвращает нижнюю границу блока для позиционирования следующего блока
    def bottom_edge
      @y - @height
    end
    
    # Возвращает левую границу блока
    def left_edge
      @x
    end
    
    # Абстрактный метод для отрисовки блока
    def draw(canvas)
      raise NotImplementedError, "Subclass must implement draw method"
    end
  end
  
  # Блок для секций согласования/утверждения
  class ApprovalBlock < BaseBlock
    attr_reader :title, :left_data, :right_data, :custom_font_size, :custom_line_spacing
    
    def initialize(page_width, page_height, title: 'УТВЕРЖДАЮ', **options)
      super(page_width, page_height, **options)
      @title = title
      @left_data = {}
      @right_data = {}
      @custom_font_size = options[:custom_font_size] || 12
      @custom_line_spacing = parse_line_spacing(options[:custom_line_spacing])
      
      # Если не заданы относительные размеры, используем разумные по умолчанию
      if @width == (@page_width - 100) && @height == 20
        @width = @page_width * 0.8  # 80% ширины страницы
        @height = @page_height * 0.15  # 15% высоты страницы
      end
    end
    
    def set_left_data(job1: '', job2: '', name: '', date: '')
      @left_data = {
        job1: job1,
        job2: job2,
        name: name,
        date: date
      }
    end
    
    def set_right_data(job1: '', job2: '', name: '', date: '')
      @right_data = {
        job1: job1,
        job2: job2,
        name: name,
        date: date
      }
    end
    
    def draw(canvas)
      canvas.font('Times', style: :normal) do
        canvas.fill_color '333333'
        
        # Заголовки утверждения
        signature_width = @width / 2
        canvas.text_box @title,
          at: [@x, @y],
          width: signature_width,
          height: 20,
          size: @custom_font_size,
          overflow: :expand,
          align: :center
        
        canvas.text_box @title,
          at: [@x + signature_width, @y],
          width: signature_width,
          height: 20,
          size: @custom_font_size,
          overflow: :expand,
          align: :center
        
        # Должности левой стороны
        canvas.text_box @left_data[:job1],
          at: [@x, @y - @custom_line_spacing],
          width: signature_width,
          height: 15,
          size: @custom_font_size,
          overflow: :expand,
          align: :center
        
        canvas.text_box @left_data[:job2],
          at: [@x, @y - (@custom_line_spacing * 2)],
          width: signature_width,
          height: 15,
          size: @custom_font_size,
          overflow: :expand,
          align: :center
        
        # Должности правой стороны
        canvas.text_box @right_data[:job1],
          at: [@x + signature_width, @y - @custom_line_spacing],
          width: signature_width,
          height: 15,
          size: @custom_font_size,
          overflow: :expand,
          align: :center
        
        canvas.text_box @right_data[:job2],
          at: [@x + signature_width, @y - (@custom_line_spacing * 2)],
          width: signature_width,
          height: 15,
          size: @custom_font_size,
          overflow: :expand,
          align: :center
        
        # Инициалы и фамилии
        canvas.text_box @left_data[:name],
          at: [@x, @y - (@custom_line_spacing * 3)],
          width: signature_width,
          height: 15,
          size: @custom_font_size,
          overflow: :expand,
          align: :center
        
        canvas.text_box @right_data[:name],
          at: [@x + signature_width, @y - (@custom_line_spacing * 3)],
          width: signature_width,
          height: 15,
          size: @custom_font_size,
          overflow: :expand,
          align: :center
        
        # Даты
        canvas.text_box @left_data[:date],
          at: [@x, @y - (@custom_line_spacing * 4)],
          width: signature_width,
          height: 15,
          size: @custom_font_size,
          overflow: :expand,
          align: :center
        
        canvas.text_box @right_data[:date],
          at: [@x + signature_width, @y - (@custom_line_spacing * 4)],
          width: signature_width,
          height: 15,
          size: @custom_font_size,
          overflow: :expand,
          align: :center
      end
      
      # Обновляем высоту блока на основе содержимого
      @height = @custom_line_spacing * 5  # 5 строк с интервалами
    end
  end
  
  # Обычный текстовый блок
  class TextBlock < BaseBlock
    attr_reader :text, :custom_font_size, :custom_alignment
    
    def initialize(page_width, page_height, text: '', custom_alignment: :center, **options)
      super(page_width, page_height, **options)
      @text = text
      @custom_font_size = options[:custom_font_size] || 12
      @custom_alignment = custom_alignment
      @custom_line_spacing = parse_line_spacing(options[:custom_line_spacing])
    end
    
    def set_text(text)
      @text = text
    end
    
    def add_line(text)
      @text = @text.empty? ? text : "#{@text}\n#{text}"
    end
    
    def draw(canvas)
      canvas.font('Times', style: :normal) do
        canvas.fill_color '333333'
        
        # Разбиваем текст на строки
        lines = @text.split("\n")
        
        lines.each_with_index do |line, index|
          canvas.text_box line,
            at: [@x, @y - (index * @custom_line_spacing)],
            width: @width,
            height: 20,
            size: @custom_font_size,
            overflow: :expand,
            align: @custom_alignment
        end
        
        # Обновляем высоту блока на основе количества строк
        @height = lines.length * @custom_line_spacing
      end
    end
  end
  
  # Блок для отображения количества листов
  class PageCountBlock < BaseBlock
    attr_reader :custom_font_size
    
    def initialize(page_width, page_height, **options)
      super(page_width, page_height, **options)
      @custom_font_size = options[:custom_font_size] || 12
      
      # Если не заданы относительные размеры, используем разумные по умолчанию
      if @width == (@page_width - 100) && @height == 20
        @width = @page_width * 0.2  # 20% ширины страницы
        @height = @page_height * 0.05  # 5% высоты страницы
        # Позиционируем по центру страницы
        @x = (@page_width - @width) / 2
        @y = (@page_height + @height) / 2
      end
    end
    
    def draw(canvas, page_count)
      # Не печатаем количество листов, если документ еще не полностью обработан
      return if page_count <= 1
      
      canvas.font('Times', style: :normal) do
        canvas.fill_color '333333'
        
        canvas.draw_text "Листов #{page_count}", 
          at: [@x, @y], 
          size: @custom_font_size
      end
    end
  end
  
  # Блок для одного подписанта (универсальный)
  class SignatureBlock < BaseBlock
    attr_reader :title, :signature_data, :custom_font_size, :custom_line_spacing
    
    def initialize(page_width, page_height, title: '', **options)
      super(page_width, page_height, **options)
      @title = title
      @signature_data = {}
      @custom_font_size = options[:custom_font_size] || 12
      @custom_line_spacing = parse_line_spacing(options[:custom_line_spacing])
      
      # Если не заданы относительные размеры, используем разумные по умолчанию
      if @width == (@page_width - 100) && @height == 20
        @width = @page_width * 0.2  # 20% ширины страницы для одного подписанта
        @height = @page_height * 0.1  # 10% высоты страницы
      end
    end
    
    def set_signature_data(job1: '', job2: '', name: '', date: '')
      @signature_data = {
        job1: Array(job1),  # Преобразуем в массив
        job2: Array(job2),  # Преобразуем в массив
        name: Array(name),  # Преобразуем в массив
        date: Array(date)   # Преобразуем в массив
      }
    end
    
    def draw(canvas)
      canvas.font('Times', style: :normal) do
        canvas.fill_color '333333'
        
        # Заголовок (если есть)
        if !@title.empty?
          canvas.text_box @title,
            at: [@x, @y],
            width: @width,
            height: 20,
            size: @custom_font_size,
            overflow: :expand,
            align: :center
        end
        
        # Должности (обрабатываем массивы строк)
        y_offset = @custom_line_spacing
        @signature_data[:job1].each do |line|
          canvas.text_box line,
            at: [@x, @y - y_offset],
            width: @width,
            height: 15,
            size: @custom_font_size,
            overflow: :expand,
            align: :center
          y_offset += @custom_line_spacing
        end
        
        @signature_data[:job2].each do |line|
          canvas.text_box line,
            at: [@x, @y - y_offset],
            width: @width,
            height: 15,
            size: @custom_font_size,
            overflow: :expand,
            align: :center
          y_offset += @custom_line_spacing
        end
        
        # Инициалы и фамилия с дополнительными отступами
        @signature_data[:name].each do |line|
          canvas.text_box line,
            at: [@x, @y - y_offset],
            width: @width,
            height: 15,
            size: @custom_font_size,
            overflow: :expand,
            align: :center
          y_offset += @custom_line_spacing
        end
        
        # Дата с дополнительным отступом после подписи
        @signature_data[:date].each do |line|
          canvas.text_box line,
            at: [@x, @y - y_offset],
            width: @width,
            height: 15,
            size: @custom_font_size,
            overflow: :expand,
            align: :center
          y_offset += @custom_line_spacing
        end
      end
      
      # Обновляем высоту блока на основе содержимого
      total_lines = @signature_data[:job1].length + @signature_data[:job2].length + 
                   @signature_data[:name].length + @signature_data[:date].length
      @height = @custom_line_spacing * total_lines
    end
  end
end