require_relative 'title_page_blocks'

# Модуль для генерации листа утверждения в стиле ГОСТ
module ConvertApprovalPageGost
  
  def generate_approval_page_gost(doc)
    puts "🎯 Генерируем лист утверждения в стиле ГОСТ..."
    
    canvas do
      # Регистрируем шрифт Times
      font_families.update("Times" => {
        normal: "resources/fonts/times-new-roman-normal.ttf",
        bold: "resources/fonts/times-new-roman-bold.ttf",
        italic: "resources/fonts/times-new-roman-italic.ttf",
        bold_italic: "resources/fonts/times-new-roman-bold-italic.ttf"
      })
      
      # Рисуем рамку страницы с приставкой (как в original_frame)
      draw_page_frame(doc)
      
      # Рисуем содержимое листа утверждения
      draw_approval_content(doc)
    end
    
    puts "✅ Лист утверждения в стиле ГОСТ сгенерирован"
  end
  
  
  private
  
  # Рисует рамку страницы с настраиваемыми отступами (скопировано из original_frame)
  def draw_page_frame(doc)
    # Получаем размеры страницы
    page_width = page.dimensions[2]  # Ширина страницы
    page_height = page.dimensions[3] # Высота страницы
    
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
    
    # # Рисуем прямоугольник рамки
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
        text_y = current_y - (height / 2) - (11 * TitlePageBlocks::MM_TO_POINTS)  # -15+4=-11
        
        # Вторую и третью надписи снизу опускаем на 1мм
        text_y -= (1 * TitlePageBlocks::MM_TO_POINTS) if index == 1 || index == 2
        
        # Устанавливаем черный цвет для текста
        fill_color '000000'
        
        rotate(90, origin: [text_x, text_y]) do
          draw_text text_labels[index], at: [text_x, text_y], size: 12
        end
        current_y -= height
      end
    end
  end
  
  # Рисует содержимое листа утверждения (используем точную логику из original_frame)
  def draw_approval_content(doc)
    # Получаем размеры страницы (точно как в original_frame)
    page_width = page.dimensions[2]  # Ширина страницы
    page_height = page.dimensions[3] # Высота страницы
    
    # Параметры рамки (точно как в original_frame)
    frame_margin_top = (doc.attr('frame_margin_top') || 5).to_f * TitlePageBlocks::MM_TO_POINTS
    frame_margin_right = (doc.attr('frame_margin_right') || 5).to_f * TitlePageBlocks::MM_TO_POINTS
    frame_margin_bottom = (doc.attr('frame_margin_bottom') || 5).to_f * TitlePageBlocks::MM_TO_POINTS
    frame_margin_left = (doc.attr('frame_margin_left') || 20).to_f * TitlePageBlocks::MM_TO_POINTS
    
    # Размеры приставки (точно как в original_frame)
    attachment_width = 12 * TitlePageBlocks::MM_TO_POINTS
    
    # Координаты основного содержимого (точно как в original_frame)
    content_x = frame_margin_left
    content_y = page_height - frame_margin_top
    content_width = page_width - frame_margin_left - frame_margin_right
    content_height = page_height - frame_margin_top - frame_margin_bottom
    
    # Рисуем содержимое листа утверждения используя данные из approval-page.adoc
    draw_approval_sheet_content(doc, content_x, content_y, content_width, content_height)
  end
  
  # Рисует содержимое листа утверждения используя систему блоков
  def draw_approval_sheet_content(doc, content_x, content_y, content_width, content_height)
    # Получаем размеры страницы
    page_width = page.dimensions[2]
    page_height = page.dimensions[3]
    
    # Создаем блоки для листа утверждения
    blocks = []
    
    # Блок "СОГЛАСОВАНО" (слева)
    signature_block_left = TitlePageBlocks::SignatureBlock.new(
      page_width, page_height,
      title: 'СОГЛАСОВАНО',
      left_position: 2.0,      # 2 см от левого края
      top_position: 3.0,        # 3 см от верхнего края
      width: 8.0,               # 8 см ширина
      height: 4.0,              # 4 см высота
      custom_line_spacing: 0.7,  # 0.7 см интервал между строками
      custom_font_size: 12
    )
    
    signature_block_left.set_signature_data(
      job1: [doc.attr('signer_1_position') || ''],
      name: ["____________ #{doc.attr('signer_1_name') || ''}", ''],
      date: ["«___» ___________ #{doc.attr('year') || ''} г."]
    )
    blocks << signature_block_left
    
    # Блок "УТВЕРЖДАЮ" (справа)
    signature_block_right = TitlePageBlocks::SignatureBlock.new(
      page_width, page_height,
      title: 'УТВЕРЖДАЮ',
      left_position: 12.0,      # 12 см от левого края
      top_position: 3.0,        # 3 см от верхнего края
      width: 8.0,               # 8 см ширина
      height: 4.0,              # 4 см высота
      custom_line_spacing: 0.7,  # 0.7 см интервал между строками
      custom_font_size: 12
    )
    
    signature_block_right.set_signature_data(
      job1: [doc.attr('signer_2_position') || ''],
      name: ["____________ #{doc.attr('signer_2_name') || ''}", ''],
      date: ["«___» ___________ #{doc.attr('year') || ''} г."]
    )
    blocks << signature_block_right
    
    # Блок с информацией о документе (в центре страницы)
    document_info_block = TitlePageBlocks::TextBlock.new(
      page_width, page_height,
      left_position: 5.0,      # 6 см от левого края (центр)
      top_position: 9.0,       # 8 см от верхнего края
      width: 12.0,             # 12 см ширина
      height: 3.0,             # 3 см высота
      custom_alignment: :center,
      custom_line_spacing: 0.8,  # 0.8 см интервал между строками
      custom_font_size: 12
    )
    
    # Формируем текст с информацией о документе
    # ВНИМАНИЕ: Здесь можно легко добавлять/удалять атрибуты из основного документа
    document_text = []
    document_text << "#{doc.attr('name_component_3') || ''} #{doc.attr('name_component_4') || ''}" # Название документа
    document_text << (doc.attr('name_dokument_master') || '')  # Название документа
    document_text << "Лист утверждения"  # Название документа
    document_text << "#{doc.attr('code') || ''} #{doc.attr('code_document') || ''} 01-ЛУ"        # Код документа
    
    document_info_block.set_text(document_text.join("\n"))
    blocks << document_info_block
    
    # Блоки для остальных подписантов (справа, вертикально)
    signers_data = [
      { position: doc.attr('signer_3_position') || '', name: doc.attr('signer_3_name') || '' },
      { position: doc.attr('signer_6_position') || '', name: doc.attr('signer_6_name') || '' }
    ]
    
    signers_data.each_with_index do |signer, index|
      next if signer[:position].nil? || signer[:position].empty?
      
      signature_block = TitlePageBlocks::SignatureBlock.new(
        page_width, page_height,
        title: '',
        left_position: 12.0,      # 12 см от левого края
        top_position: 15.0 + (index * 3),  # 8 см + индекс * 2.5 см от верха
        width: 8.0,               # 8 см ширина
        height: 2.0,              # 2 см высота
        custom_line_spacing: 0.4,  # 0.5 см интервал между строками
        custom_font_size: 12
      )
      
      signature_block.set_signature_data(
        job1: [signer[:position] || ''],
        name: ["_____________#{signer[:name] || ''}",""],
        date: ["«___» ___________ #{doc.attr('lu_year') || '2025'} г."]
      )
      blocks << signature_block
    end
    
    # Блок "Литера" (внизу справа)
    text_block = TitlePageBlocks::TextBlock.new(
      page_width, page_height,
      left_position: 18.0,      # 18 см от левого края
      top_position: 27.0,       # 25 см от верхнего края
      width: 2.0,               # 2 см ширина
      height: 1.0,              # 1 см высота
      custom_font_size: 10
    )
    
    text_block.set_text("Литера")
    blocks << text_block
    
    # Рендерим все блоки (передаем canvas, который есть у нас в контексте)
    blocks.each { |block| block.draw(self) }
  end
  
  # Старый метод удален - теперь используется система блоков
  
  
end
