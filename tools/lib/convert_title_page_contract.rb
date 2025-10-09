require 'date'
require_relative 'ordinal_word_ru'
require_relative 'title_page_blocks'

# Модуль для создания титульной страницы контракта с абсолютными координатами
# 
# Демонстрирует использование абсолютных координат (в сантиметрах) для контрактных документов.
# Все позиции задаются в сантиметрах от краев страницы.
#
# Используется для: атрибута :custom_title_page: contract
module ConvertTitlePageContract
  include TitlePageOrdinalWord
  
  def self.supports_type?(type)
    type == 'contract'
  end
  
  def self.supported_types
    ['contract']
  end

  def ink_title_page(doc)
    # Получаем размеры страницы
    page_width = page.dimensions[2]  # Ширина страницы
    page_height = page.dimensions[3] # Высота страницы
    
    # Единый размер шрифта для всей титульной страницы
    title_page_font_size = 14
    
    # Создаем блоки с использованием абсолютных координат (в сантиметрах)
    blocks = []
    
    # 1. Блок утверждения - создаем два независимых блока подписантов
    
    # Первый подписант - заказчик (левая сторона)
    # Позиционируем в 3 см от левого края, 2 см от верха, размер 8x4 см
    approval_signature_block_1 = TitlePageBlocks::SignatureBlock.new(
      page_width, page_height,
      title: 'УТВЕРЖДАЮ',
      left_position: 3.0,         # 3 см от левого края
      top_position: 2.0,          # 2 см от верхнего края
      width: 8.0,                 # 8 см ширина
      height: 4.0,                # 4 см высота
      custom_line_spacing: 0.6,  # 0.7 см интервал между строками
      custom_font_size: title_page_font_size
    )
    
    approval_signature_block_1.set_signature_data(
      job1: [doc.attr('job_customer_1') || ''],
      job2: [doc.attr('job_customer_2') || '', ''],  # Должность + пустая строка
      name: ["_____________#{doc.attr('iof_customer') || ''}"],  # Черта + фамилия
      date: ["«___» ___________ #{doc.attr('year') || ''} г."]
    )
    blocks << approval_signature_block_1
    
    # Второй подписант - исполнитель (правая сторона)
    # Позиционируем в 15 см от левого края, 2 см от верха, размер 8x4 см
    approval_signature_block_2 = TitlePageBlocks::SignatureBlock.new(
      page_width, page_height,
      title: 'УТВЕРЖДАЮ',
      left_position: 12.0,        # 15 см от левого края
      top_position: 2.0,          # 2 см от верхнего края
      width: 8.0,                 # 8 см ширина
      height: 4.0,                # 4 см высота
      custom_line_spacing: 0.7,  # 0.7 см интервал между строками
      custom_font_size: title_page_font_size
    )
    
    approval_signature_block_2.set_signature_data(
      job1: [doc.attr('job_executor_1') || ''],
      job2: [doc.attr('job_executor_2') || '', ''],  # Должность + пустая строка
      name: ["_____________#{doc.attr('iof_executor') || ''}"],  # Черта + фамилия
      date: ["«___» ___________ #{doc.attr('year') || ''} г."]
    )
    blocks << approval_signature_block_2
    
    # 2. Блок информации о компоненте - позиционируем под блоком утверждения
    # Позиционируем в 3 см от левого края, 7 см от верха, размер 16x2 см
    component_text = [
      doc.attr('name_component_1') || '',
      doc.attr('name_component_2') || '',
      "#{doc.attr('name_component_3') || ''} #{doc.attr('name_component_4') || ''}".strip
    ].reject(&:empty?).join("\n")
    
    component_block = TitlePageBlocks::TextBlock.new(
      page_width, page_height,
      text: component_text,
      left_position: 3.0,         # 3 см от левого края
      top_position: 7.0,          # 7 см от верхнего края
      width: 16.0,                # 16 см ширина
      height: 2.0,                # 2 см высота
      custom_alignment: :center,
      custom_line_spacing: 0.6,     # 0.6 см интервал между строками
      custom_font_size: title_page_font_size  # Единый размер шрифта
    )
    
    blocks << component_block
    
    # 3. Блок названия документа - позиционируем в центре страницы
    # Позиционируем в 3 см от левого края, 10 см от верха, размер 16x3 см
    document_text = [
      doc.attr('name_dokument_master') || '',
      doc.attr('name_dokument_slave') || ''
    ].reject(&:empty?).join("\n")
    
    document_block = TitlePageBlocks::TextBlock.new(
      page_width, page_height,
      text: document_text,
      left_position: 3.0,         # 3 см от левого края
      top_position: 10.0,         # 10 см от верхнего края
      width: 16.0,                # 16 см ширина
      height: 3.0,                # 3 см высота
      custom_alignment: :center,
      custom_line_spacing: 17,    # Интервал между строками
      custom_font_size: title_page_font_size  # Единый размер шрифта
    )
    
    blocks << document_block
    
    # 4. Блок контракта - позиционируем под названием документа
    # Позиционируем в 3 см от левого края, 14 см от верха, размер 16x2 см
    contract_text = [
      "#{doc.attr('contract_name') || ''} #{doc.attr('contract_number') || ''}",
      "#{doc.attr('state_name') || ''} #{doc.attr('state_сontract_number') || ''}"
    ].reject(&:empty?).join("\n")
    
    contract_block = TitlePageBlocks::TextBlock.new(
      page_width, page_height,
      text: contract_text,
      left_position: 3.0,         # 3 см от левого края
      top_position: 12.0,         # 14 см от верхнего края
      width: 16.0,                # 16 см ширина
      height: 2.0,                # 2 см высота
      custom_alignment: :center,
      custom_line_spacing: 17,    # Интервал между строками
      custom_font_size: title_page_font_size  # Единый размер шрифта
    )
    
    blocks << contract_block
    
    # 5. Блок версии - позиционируем под блоком контракта
    # Позиционируем в 3 см от левого края, 16 см от верха, размер 16x2 см
    version_text = "#{doc.attr('code') || ''} #{doc.attr('code_document') || ''} 01"
    
    
    version_block = TitlePageBlocks::TextBlock.new(
      page_width, page_height,
      text: version_text,
      left_position: 3.0,         # 3 см от левого края
      top_position: 14.0,          # 16 см от верхнего края
      width: 16.0,                 # 16 см ширина
      height: 2.0,                 # 2 см высота
      custom_alignment: :center,
      custom_line_spacing: 0.6,     # 0.6 см интервал между строками
      custom_font_size: title_page_font_size  # Единый размер шрифта
    )
    
    blocks << version_block
    
    # 6. Блок количества листов - позиционируем в центре страницы
    # Позиционируем в 9 см от левого края, 18 см от верха, размер 4x1 см
    page_count_block = TitlePageBlocks::PageCountBlock.new(
      page_width, page_height,
      left_position: 10.0,          # 9 см от левого края (центр)
      top_position: 16.0,          # 18 см от верхнего края
      width: 4.0,                  # 4 см ширина
      height: 1.0,                 # 1 см высота
      custom_font_size: title_page_font_size  # Единый размер шрифта
    )

    # 7. Блок согласования - позиционируем в нижней части страницы
    # Позиционируем в 3 см от левого края, 24 см от верха, размер 8x4 см
    agreement_block = TitlePageBlocks::SignatureBlock.new(
      page_width, page_height,
      title: 'СОГЛАСОВАНО',
      left_position: 3.0,         # 3 см от левого края
      top_position: 21.0,          # 24 см от верхнего края
      width: 8.0,                  # 8 см ширина
      height: 4.0,                 # 4 см высота
      custom_line_spacing: 0.6,     # 0.6 см интервал между строками
      custom_font_size: title_page_font_size  # Единый размер шрифта
    )
    
    # Настраиваем данные для согласования
    agreement_block.set_signature_data(
      job1: [doc.attr('job_concordant_1') || ''],
      job2: [doc.attr('job_concordant_2') || '', ''],  # Должность + пустая строка
      name: ["_____________ #{doc.attr('iof_concordant') || ''}"],  # Черта + фамилия
      date: ["«___» ___________ #{doc.attr('year') || ''} г."]
    )
    
    blocks << agreement_block

  # 2. Блок год
  document_text = [
    doc.attr('year') || ''
  ].reject(&:empty?).join("\n")
  
  document_block = TitlePageBlocks::TextBlock.new(
    page_width, page_height,
    text: document_text,
    left_position: 3.0,       # 3 см от левого края
    top_position: 27.5,       # 10 см от верхнего края
    width: 16.0,              # 16 см ширина
    height: 3.0,              # 3 см высота
    custom_alignment: :center,
    custom_line_spacing: 1.6,   # 0.6 см интервал между строками
    custom_font_size: title_page_font_size  # Единый размер шрифта
  )
  
  blocks << document_block


    # Отрисовываем все блоки
    canvas do
      font_size 12 do
        stroke_color '333333'
        fill_color '333333'
        
        blocks.each do |block|
          block.draw(self)
        end
        
        # Добавляем количество листов
        page_count_block.draw(self, page_count)
      end
    end
  end
  
end
