require 'date'
require_relative 'ordinal_word_ru'
require_relative 'title_page_blocks'

# Модуль для создания титульной страницы оригинального типа с абсолютными координатами
# 
# Демонстрирует использование абсолютных координат (в сантиметрах) вместо относительных.
# Все позиции задаются в сантиметрах от краев страницы.
#
# Используется для: атрибута :custom_title_page: original
module ConvertTitlePageOriginal
  include TitlePageOrdinalWord
  
  def self.supports_type?(type)
    type == 'original'
  end
  
  def self.supported_types
    ['original']
  end

  def ink_title_page(doc)
    # Получаем размеры страницы
    page_width = page.dimensions[2]  # Ширина страницы
    page_height = page.dimensions[3] # Высота страницы
    
    # Единый размер шрифта для всей титульной страницы
    title_page_font_size = 14
    
    # Создаем блоки с использованием абсолютных координат (в сантиметрах)
    blocks = []
    
    # 1. Блок утверждения - только исполнитель (правая сторона)
    # Позиционируем в 15 см от левого края, 2 см от верха, размер 8x4 см
    approval_signature_block = TitlePageBlocks::SignatureBlock.new(
      page_width, page_height,
      title: 'Утвержден',
      left_position: 3.0,      # 15 см от левого края
      top_position: 2.0,        # 2 см от верхнего края
      width: 8.0,               # 8 см ширина
      height: 4.0,              # 4 см высота
      custom_line_spacing: 0.7,  # 0.7 см интервал между строками
      custom_font_size: title_page_font_size
    )
    
    approval_signature_block.set_signature_data(
      job1: ["––––––––––––––––––––––––––––"],  # Черта + фамилия

    # job1: [doc.attr('job_executor_1') || ''],
      # job2: [doc.attr('code_gk') || '', ''],  # Должность + пустая строка
      # name: ["_____________#{doc.attr('iof_executor') || ''}"],  # Черта + фамилия
      # date: ["«___» ___________ #{doc.attr('year') || ''} г."]
    )
    blocks << approval_signature_block

     # 2. Блок версии - позиционируем под блоком 
   
    full_code = doc.attr('full_code') || ''
    version_code = "#{full_code}-ЛУ"
    version_text = "#{version_code}"
    
    version_block = TitlePageBlocks::TextBlock.new(
      page_width, page_height,
      text: version_text,
      left_position: 5,       # 3 см от левого края
      top_position: 3.5,       # 16 см от верхнего края
      width: 8.0,              # 16 см ширина
      height: 2.0,              # 2 см высота
      custom_alignment: :left,
      custom_line_spacing: 0.6,   # 0.6 см интервал между строками
      custom_font_size: title_page_font_size  # Единый размер шрифта
    )
    
    blocks << version_block



    # 3. Блок названия документа - позиционируем в центре страницы
    # Позиционируем в 3 см от левого края, 10 см от верха, размер 16x3 см
    full_code = doc.attr('full_code') || ''
    document_text = [
      doc.attr('name_component') || '',
      doc.attr('name_document_master') || '',
      doc.attr('name_document_slave') || '',
      full_code
    ].reject(&:empty?).join("\n")
    
    document_block = TitlePageBlocks::TextBlock.new(
      page_width, page_height,
      text: document_text,
      left_position: 3.0,       # 3 см от левого края
      top_position: 9.0,       # 10 см от верхнего края
      width: 16.0,              # 16 см ширина
      height: 3.0,              # 3 см высота
      custom_alignment: :center,
      custom_line_spacing: 1.0,   # 0.6 см интервал между строками
      custom_font_size: title_page_font_size  # Единый размер шрифта
    )
    blocks << document_block


    # 4. Блок количества листов - позиционируем в центре страницы
    # Позиционируем в 9 см от левого края, 18 см от верха, размер 4x1 см
    page_count_block = TitlePageBlocks::PageCountBlock.new(
      page_width, page_height,
      left_position: 10.0,        # 9 см от левого края (центр)
      top_position: 14.0,       # 18 см от верхнего края
      width: 4.0,               # 4 см ширина
      height: 1.0,              # 1 см высота
      custom_font_size: title_page_font_size  # Единый размер шрифта
    )

    # 5. Блок год
    document_text = [
      doc.attr('year') || ''
    ].reject(&:empty?).join("\n")
    
    document_block = TitlePageBlocks::TextBlock.new(
      page_width, page_height,
      text: document_text,
      left_position: 3.0,       # 3 см от левого края
      top_position: 26.0,       # 10 см от верхнего края
      width: 16.0,              # 16 см ширина
      height: 3.0,              # 3 см высота
      custom_alignment: :center,
      custom_line_spacing: 1.6,   # 0.6 см интервал между строками
      custom_font_size: title_page_font_size  # Единый размер шрифта
    )
    
    blocks << document_block


    # # Блок "Литера" (внизу справа)
    # text_block = TitlePageBlocks::TextBlock.new(
    #   page_width, page_height,
    #   left_position: 18.0,      # 18 см от левого края
    #   top_position: 27.0,       # 25 см от верхнего края
    #   width: 2.0,               # 2 см ширина
    #   height: 1.0,              # 1 см высота
    #   custom_font_size: title_page_font_size
    # )
    
    # text_block.set_text("Литера")
    # blocks << text_block

    # Отрисовываем все блоки
    canvas do
      font_size 12 do
        stroke_color '333333'
        fill_color '333333'
        
        blocks.each do |block|
          block.draw(self)
        end

        # Рисуем рамку страницы
        draw_page_frame(doc)

        # Добавляем количество листов
        page_count_block.draw(self, page_count)
      end
    end
  end

  # Рисует рамку страницы с настраиваемыми отступами
  def draw_page_frame(doc)
    # Получаем размеры страницы
    page_width = page.dimensions[2]  # Ширина страницы
    page_height = page.dimensions[3] # Высота страницы
    
    # Высота строк снизу вверх (в миллиметрах)
    row_heights = [35, 25, 25, 35, 25]
    stroke_color '777777'
    # Параметры рамки (в миллиметрах)
    # Отступы: top=5мм, right=5мм, bottom=5мм, left=20мм
    frame_margin_top = (doc.attr('frame_margin_top') || 5).to_f * TitlePageBlocks::MM_TO_POINTS
    frame_margin_right = (doc.attr('frame_margin_right') || 5).to_f * TitlePageBlocks::MM_TO_POINTS
    frame_margin_bottom = (doc.attr('frame_margin_bottom') || 5).to_f * TitlePageBlocks::MM_TO_POINTS
    frame_margin_left = (doc.attr('frame_margin_left') || 20).to_f * TitlePageBlocks::MM_TO_POINTS
    
    # Толщина линии рамки (в миллиметрах)
    frame_line_width = (doc.attr('frame_line_width') || 0.3).to_f * TitlePageBlocks::MM_TO_POINTS
    
    # Вычисляем координаты рамки
    frame_x = frame_margin_left
    frame_y = page_height - frame_margin_top
    frame_width = page_width - frame_margin_left - frame_margin_right
    frame_height = page_height - frame_margin_top - frame_margin_bottom
    
    # Устанавливаем толщину линии
    line_width(frame_line_width)
    
    # Рисуем прямоугольник всей большой рамки рамки
    # rectangle([frame_x, frame_y], frame_width, frame_height)
    # stroke
    
    # Рисуем приставку к рамке
    # Размеры приставки (в пикселях)
    attachment_width = 12 * TitlePageBlocks::MM_TO_POINTS  # общая ширина
    left_width = 5 * TitlePageBlocks::MM_TO_POINTS         # левый столбец
    right_width = 7 * TitlePageBlocks::MM_TO_POINTS        # правый столбец
    
    # Высота строк снизу вверх (в пикселях) - используем те же значения что и для frame_margin_bottom
    row_heights_pixels = row_heights.map { |h| h * TitlePageBlocks::MM_TO_POINTS }
    
    # Координаты приставки
    attachment_x = frame_x - attachment_width
    attachment_y = frame_margin_bottom + (row_heights.sum * TitlePageBlocks::MM_TO_POINTS)
    
    # Рисуем прямоугольники приставки (снизу вверх)
    current_y = attachment_y
    row_heights_pixels.each_with_index do |height, index|
      # Левый столбец
      stroke_rectangle [attachment_x, current_y], left_width, height
      # Правый столбец
      stroke_rectangle [attachment_x + left_width, current_y], right_width, height
      current_y -= height
    end
    
    # Добавляем текст приставки (вертикально снизу вверх)
    # Порядок снизу вверх: "Инв. № подл.", "Подп. и дата", "Взам. инв. №", "Инв. № дубл.", "Подп. и дата"
    text_labels = ["Подп. и дата", "Инв. № дубл.", "Взам. инв. №", "Подп. и дата", "Инв. № подл."]
    
    font('Times', style: :italic) do
      current_y = attachment_y
      row_heights_pixels.each_with_index do |height, index|
        # Позиция текста: центр левого столбца + сдвиги
        text_x = attachment_x + (left_width / 2) + (1.5 * TitlePageBlocks::MM_TO_POINTS)
        text_y = current_y - (height / 2) - (11 * TitlePageBlocks::MM_TO_POINTS)  
        
        # Вторую и третью надписи снизу опускаем на 1мм
        text_y -= (1 * TitlePageBlocks::MM_TO_POINTS) if index == 1 || index == 2
        
        rotate(90, origin: [text_x, text_y]) do
          draw_text text_labels[index], at: [text_x, text_y], size: 12
        end
        current_y -= height
      end
    end
  end
  
end
