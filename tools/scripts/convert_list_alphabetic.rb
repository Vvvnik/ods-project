module ConvertListAlphabetic

  def convert_ulist(node)
    add_dest_for_block node if node.id
    # Для всех уровней ненумерованного списка используем маркер '–'
    @list_bullets << :dash
    convert_list node
    @list_bullets.pop
  end

  def convert_olist(node)
    add_dest_for_block node if node.id
    
    # Определяем стиль нумерации в зависимости от уровня вложенности
    case @list_numerals.size + 1
    when 1
      # Первый уровень: 1) 2) 3)
      list_numeral = 1
      node.style = 'arabic'
    when 2
      # Второй уровень: а) б) в)
      list_numeral = 'а'
      node.style = 'loweralpha'
    else
      # Третий и последующие уровни: -
      list_numeral = '–'
      node.style = 'none'
    end

    if (start = (node.attr 'start') || ((node.option? 'reversed') ? node.items.size : nil))
      if (start = start.to_i) > 1
        (start - 1).times { list_numeral = list_numeral.next }
      elsif start < 1 && !(::String === list_numeral)
        (start - 1).abs.times { list_numeral = list_numeral.pred }
      end
    end

    @list_numerals << list_numeral
    convert_list node
    @list_numerals.pop
  end

  def convert_list(node)
    ink_caption node, category: :list, labeled: false if node.title?

    opts = {}
    if (text_align = resolve_text_align_from_role node.roles)
      opts[:align] = text_align
    elsif (text_align = @theme.list_text_align&.to_sym)
      opts[:align] = text_align
    end

    line_metrics = calc_line_metrics @base_line_height

    # Определяем отступ в зависимости от уровня вложенности
    base_indent = @theme.list_indent || 16
    current_level = @list_numerals.size + @list_bullets.size
    if base_indent.to_f.zero?
      # Тема задает 0 – используем собственный шаг (можно переопределить атрибутом :list-level-step: в документе)
      # step = (node.document.attr('list-level-step') || 14).to_f
      step = (node.document.attr('list-level-step') || @theme.list_level_step || 30).to_f
      list_indent = case current_level
                    when 1 then 0
                    when 2 then step
                    else step
                    end
    else
      list_indent = current_level >= 2 ? (base_indent / 3.0) : base_indent
    end

    # Для списков без маркеров корректируем отступ
    if (node.context == :ulist && !@list_bullets[-1]) || (node.context == :olist && !@list_numerals[-1])
      list_indent = 0 if node.style == 'unstyled'
    end

    indent list_indent do
      node.items.each do |item|
        allocate_space_for_list_item line_metrics
        convert_list_item item, node, opts
      end
    end

    theme_margin :prose, :bottom, (next_enclosed_block node) unless node.nested?
  end  

  def convert_list_item(node, list, opts = {})
    marker_style = {
      font_color: @theme.list_marker_font_color || @font_color,
      font_family: font_family,
      font_size: font_size,
      line_height: @base_line_height
    }
    
    case list.context
    when :olist
      if (index = @list_numerals.last)
        # Формируем маркер для нумерованного списка
        case @list_numerals.size
        when 1 then marker = "#{index})"  # 1) 2) 3)
        when 2 then marker = "#{index})"  # а) б) в)
        else        marker = '–'          # -
        end

        dir = (list.option? 'reversed') ? :pred : :next
        @list_numerals[-1] = index.public_send(dir)
        
        # Применяем стили для маркера
        [:font_color, :font_family, :font_size, :font_style, :line_height].each do |prop|
          marker_style[prop] = @theme["olist_marker_#{prop}"] || marker_style[prop]
        end
      end
    when :ulist
      # Всегда используем '–' для ненумерованных списков
      marker = '–'
      
      # Применяем стили для маркера
      [:font_color, :font_family, :font_size, :font_style, :line_height].each do |prop|
        marker_style[prop] = @theme["ulist_marker_#{prop}"] || marker_style[prop]
      end
    end

    # Остальная часть метода остается без изменений
    if marker
      if marker_style[:font_family] == 'fa'
        log :info, 'deprecated fa icon set found in theme; use fas, far, or fab instead'
        marker_style[:font_family] = FontAwesomeIconSets.find {|c| (icon_font_data c).yaml[c].value? marker } || 'fas'
      end
      
      marker_style[:font_style] &&= marker_style[:font_style].to_sym
      marker_gap = rendered_width_of_char 'x'
      
      font(marker_style[:font_family], size: marker_style[:font_size], style: marker_style[:font_style]) do
        marker_width = rendered_width_of_string(marker)
        character_spacing_correction = 0
        
        character_spacing(-0.5) do
          character_spacing_correction = 0.5 if rendered_width_of_char('x', character_spacing: -0.5) == marker_gap
        end
        
        marker_height = height_of_typeset_text(marker, line_height: marker_style[:line_height], single_line: true)
        # Определяем уровень вложенности
               # indent_level = list.context == :ulist ? @list_bullets.size : @list_numerals.size
               
               # Определяем смещение для каждого уровня
               # custom_indent =
               #   case indent_level
               #   when 1 then 0      # базовый отступ
               #   when 2 then 8      # 2 уровень – ближе к тексту
               #   else 16            # 3 и глубже – ещё ближе
               #   end
               
               # Красная строка: первая строка отступает вправо от маркера
              # First-line indent: shift text after marker by 1 cm beyond the marker gap
              # тут меняем отступ для красной строки
              first_line_indent_pt = 43 
              marker_indent = marker_gap + first_line_indent_pt
              start_position = bounds.left - marker_width - marker_gap + character_spacing_correction 
                
        float do
          advance_page if @media == 'prepress' && cursor < marker_height
          flow_bounding_box(position: start_position, width: marker_width + marker_indent) do

            ink_prose(marker,
              align: :right,
              character_spacing: -0.5,
              color: marker_style[:font_color],
              inline_format: false,
              line_height: marker_style[:line_height],
              style: marker_style[:font_style],
              margin: 0,
              normalize: false,
              single_line: true)
          end
        end
      end
    end

    opts = opts.merge(margin_bottom: 0, normalize_line_height: true)
    # First-line indent for list item content (paragraph-style red line)
    # тут меняем отступ для красной строки
    first_line_indent_pt = 48 # 1 cm
    opts = opts.merge(indent_paragraphs: first_line_indent_pt)
    if node
      if node.compound?
        opts.delete(:margin_bottom)
      elsif next_enclosed_block(node, descend: true)
        opts[:margin_bottom] = @theme.list_item_spacing
      end
    end
    traverse_list_item(node, list.context, opts)
  end
  
  # Автоматическая генерация листа утверждения если нужно
  def generate_approval_page_if_needed(doc)
    approval_page_type = doc.attr('approval-page')
    return unless approval_page_type
    
    # Проверяем, что атрибут не равен false
    if approval_page_type.to_s.downcase == 'false'
      # puts "⏭️  Атрибут :approval-page: false, пропускаем генерацию ЛУ"
      return
    end
    
    # puts "🔄 Найден атрибут :approval-page: #{approval_page_type}, генерируем лист утверждения..."
    
    # Получаем путь к основному документу
    doc_path = doc.attr('docfile') || doc.attr('docname')
    return unless doc_path
    
    # Определяем директорию основного документа
    doc_dir = File.dirname(doc_path)
    doc_name = File.basename(doc_path, '.adoc')
    
    # Теперь используется встроенный шаблон - файл approval-page.adoc не нужен
    
    # Генерируем лист утверждения используя ApprovalPageGenerator
    begin
      require_relative '../lib/approval_page_generator'
      
      approval_pdf_path = File.join(doc_dir, 'approval-page.pdf')
      
      # Используем новый генератор с встроенным шаблоном
      success = ApprovalPageGenerator.generate_approval_page(doc, nil, doc_dir)
      
      if success
      # puts "✅ Лист утверждения сгенерирован в директории: #{doc_dir}"
      else
        puts "❌ Ошибка при генерации листа утверждения"
      end
      
    rescue => e
      puts "❌ Ошибка при генерации листа утверждения: #{e.message}"
    end
  end
end
