require_relative 'title_page_blocks'

# Модуль для оригинального оформления других страниц
# Страницы с полными рамками и колонтитулами
module ConvertOtherPageOriginal
  
  def self.supports_type?(type)
    type == 'original'
  end
  
  def self.supported_types
    ['original']
  end

  def ink_other_page_original(doc)

    fill_color '777777'
    draw_text page_number.to_s, at: [page_width / 2 - 40, - 40], size: 12

  end

end
