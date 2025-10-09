require_relative 'title_page_blocks'

# Модуль для оригинального оформления других страниц с рамками
# Страницы с полными рамками и колонтитулами
module ConvertOtherPageOriginalFrame
  
  def self.supports_type?(type)
    type == 'original_frame'
  end
  
  def self.supported_types
    ['original_frame']
  end

  def ink_other_page_original_frame(doc)
    canvas do
      # Регистрируем шрифт Times
      font_families.update("Times" => {
        normal: "resources/fonts/times-new-roman-normal.ttf",
        bold: "resources/fonts/times-new-roman-bold.ttf",
        italic: "resources/fonts/times-new-roman-italic.ttf",
        bold_italic: "resources/fonts/times-new-roman-bold-italic.ttf"
      })
      
      # Рисуем рамку страницы с приставкой
      draw_other_page_frame(doc)
    end
  end

  # Рисует рамку страницы с настраиваемыми отступами
  def draw_other_page_frame(doc)
    # Получаем размеры страницы
    page_width = page.dimensions[2]  # Ширина страницы
    page_height = page.dimensions[3] # Высота страницы
    stroke_color '777777'
    # Высота строк снизу вверх (в миллиметрах)
    row_heights = [35, 25, 25, 35, 25]
    
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
    
    # Рисуем прямоугольник рамки
    rectangle([frame_x, frame_y], frame_width, frame_height)
    stroke

    # Рисуем нижнюю рамку высотой 2 см
    bottom_frame_height = 20 * TitlePageBlocks::MM_TO_POINTS    # 2 см = 20 мм
    bottom_frame_y = frame_y - frame_height + bottom_frame_height # Начинаем с низа основной рамки
    rectangle([frame_x, bottom_frame_y], frame_width, bottom_frame_height)
    stroke
    
    # Рисуем нижнюю рамку шириной 2 см и высотой 2 см
    bottom_frame_height = 20 * TitlePageBlocks::MM_TO_POINTS    # 2 см = 20 мм
    bottom_frame_y = frame_y - frame_height + bottom_frame_height # Начинаем с низа основной рамки
    rectangle([frame_width - 20 * TitlePageBlocks::MM_TO_POINTS, bottom_frame_y], 20 * TitlePageBlocks::MM_TO_POINTS, bottom_frame_height)
    stroke

    rectangle([frame_width - 20 * TitlePageBlocks::MM_TO_POINTS, bottom_frame_y - 10 * TitlePageBlocks::MM_TO_POINTS], 20 * 2 * TitlePageBlocks::MM_TO_POINTS, bottom_frame_height - 10 * TitlePageBlocks::MM_TO_POINTS)
    stroke

    # Координаты центра области для номера листа
    center_x = frame_width - 20 * TitlePageBlocks::MM_TO_POINTS + 10 * TitlePageBlocks::MM_TO_POINTS  # Центр по X
    center_y_text = 70  # Центр для текста "Лист"
    center_y_number = 40  # Центр для номера
    
    # Используем Листов в тексте и номере в text_box для центрирования
    text_box "Лист", at: [frame_width, center_y_text - 6], 
             width: 20 * TitlePageBlocks::MM_TO_POINTS, height: 12, size: 12, align: :center, valign: :center
    text_box page_number.to_s, at: [frame_width, center_y_number - 6], 
             width: 20 * TitlePageBlocks::MM_TO_POINTS, height: 12, size: 12, align: :center, valign: :center

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
        text_y = current_y - (height / 2) - (11 * TitlePageBlocks::MM_TO_POINTS)  # -15+4=-11
        
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
