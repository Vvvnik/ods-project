require 'fileutils'

# Модуль для генерации листа утверждения
# Извлекает атрибуты из основного документа и создает временный файл для ЛУ
module ApprovalPageGenerator
  
  # Генерирует лист утверждения на основе основного документа
  def self.generate_approval_page(main_doc, approval_template_path, output_dir)
    puts "🔄 Generating approval page with attributes from main document..."
    
    # Извлекаем атрибуты из основного документа
    main_attrs = extract_attributes_from_doc(main_doc)
    
    # Определяем имя документа и модуля
    doc_path = main_doc.attr('docfile') || main_doc.attr('docname')
    doc_name = File.basename(doc_path, '.adoc') if doc_path
    doc_name = doc_name.force_encoding('UTF-8') if doc_name

    # Определяем модуль из пути (например, trd, oed)
    module_name = extract_module_name(doc_path)
    
    lu_output_dir = determine_lu_output_dir(doc_path, output_dir)
    
    # Создаем уникальное имя для ЛУ
    approval_filename = "#{module_name}_#{doc_name}_LU.pdf"
    output_path = File.join(lu_output_dir, approval_filename)
    
    puts "📄 Approval page name: #{approval_filename}"
    
    # Создаем временный файл с встроенным шаблоном
    temp_file = create_temp_approval_file(main_attrs, doc_path)
    
    # Генерируем PDF из временного файла
    success = generate_approval_pdf(temp_file, output_path)
    
    # Удаляем временный файл
    File.delete(temp_file) if File.exist?(temp_file)
    
    success
  end
  
  private
  
  def self.determine_lu_output_dir(doc_path, default_output_dir)
    return default_output_dir unless doc_path
    
    path_parts = doc_path.split('/')
    pages_index = path_parts.index('pages')
    
    if pages_index
      # Генерируем ЛУ прямо в папку pages/, рядом с .adoc файлами
      pages_dir = File.join(path_parts[0..pages_index])
      
      FileUtils.mkdir_p(pages_dir) unless Dir.exist?(pages_dir)
      
      return pages_dir
    end
    
    default_output_dir
  end
  
  # Извлекает имя модуля из пути документа (например, trd, oed)
  def self.extract_module_name(doc_path)
    return 'unknown' unless doc_path
    
    # Ищем модуль в пути: .../modules/{module_name}/pages/...
    path_parts = doc_path.split('/')
    modules_index = path_parts.index('modules')
    
    if modules_index && path_parts[modules_index + 1]
      path_parts[modules_index + 1]
    else
      'unknown'
    end
  end
  
  # Извлекает атрибуты из основного документа
  def self.extract_attributes_from_doc(doc)
    attrs = {}
    
    # Основные атрибуты документа
    attrs['name_dokument_master'] = doc.attr('name_dokument_master') || ''
    attrs['code_document'] = doc.attr('code_document') || ''
    attrs['code'] = doc.attr('code') || ''
    attrs['version'] = doc.attr('version') || ''
    attrs['year'] = doc.attr('year') || ''
    
    # Подписанты (если есть в основном документе)
    attrs['signer_1_position'] = doc.attr('signer_1_position') || ''
    attrs['signer_1_name'] = doc.attr('signer_1_name') || ''
    attrs['signer_2_position'] = doc.attr('signer_2_position') || ''
    attrs['signer_2_name'] = doc.attr('signer_2_name') || ''
    attrs['signer_3_position'] = doc.attr('signer_3_position') || ''
    attrs['signer_3_name'] = doc.attr('signer_3_name') || ''
    attrs['signer_4_position'] = doc.attr('signer_4_position') || ''
    attrs['signer_4_name'] = doc.attr('signer_4_name') || ''
    attrs['signer_5_position'] = doc.attr('signer_5_position') || ''
    attrs['signer_5_name'] = doc.attr('signer_5_name') || ''
    attrs['signer_6_position'] = doc.attr('signer_6_position') || ''
    attrs['signer_6_name'] = doc.attr('signer_6_name') || ''
    
    puts "📋 Extracted attributes: #{attrs.keys.join(', ')}"
    attrs
  end
  
  # Создает временный файл с встроенным шаблоном
  def self.create_temp_approval_file(main_attrs, doc_path)
    # Определяем директорию основного документа для правильных include путей
    doc_dir = File.dirname(doc_path)
    
    # Встроенный шаблон ЛУ
    content = <<~ADOC
      include::../../ROOT/partials/contract.adoc[]
      include::../../ROOT/partials/attr_common.adoc[]
      :custom_title_page: approval_page_gost
      :nofooter:
      :notitle:
      :noheader:
      
      // Атрибуты из основного документа
      :name_dokument_master: #{main_attrs['name_dokument_master'] || ''}
      :code: #{main_attrs['code'] || 'ТЗ'}
      :version: #{main_attrs['version'] || '1'}
      :year: #{main_attrs['year'] || '2025'}
      
      // Подписанты (переопределяют дефолты из contract.adoc если есть)
      :signer_1_position: #{main_attrs['signer_1_position'] || ''}
      :signer_1_name: #{main_attrs['signer_1_name'] || ''}
      :signer_2_position: #{main_attrs['signer_2_position'] || ''}
      :signer_2_name: #{main_attrs['signer_2_name'] || ''}
      :signer_3_position: #{main_attrs['signer_3_position'] || ''}
      :signer_3_name: #{main_attrs['signer_3_name'] || ''}
      :signer_4_position: #{main_attrs['signer_4_position'] || ''}
      :signer_4_name: #{main_attrs['signer_4_name'] || ''}
      :signer_5_position: #{main_attrs['signer_5_position'] || ''}
      :signer_5_name: #{main_attrs['signer_5_name'] || ''}
      :signer_6_position: #{main_attrs['signer_6_position'] || ''}
      :signer_6_name: #{main_attrs['signer_6_name'] || ''}
    ADOC
    
    # Создаем временный файл в директории основного документа
    temp_path = File.join(doc_dir, "approval_page_temp_#{Time.now.to_i}.adoc")
    File.write(temp_path, content, encoding: 'UTF-8')
    
    puts "📝 Created temporary file: #{temp_path}"
    temp_path
  end
  
  # Генерирует PDF из временного файла
  def self.generate_approval_pdf(temp_file, output_path)
    puts "🎯 Generating approval page PDF..."
    
    # Команда для генерации PDF
    cmd = [
      "asciidoctor-pdf",
      "-r asciidoctor-kroki",
      "-r ./tools/scripts/convert_ascii_to_pdf.rb",
      "-a kroki-default-format=png",
      "-a kroki-server-url=#{ENV.fetch('KROKI_SERVER_URL', 'http://localhost:8000')}",
      # Тема будет определена автоматически в конвертере
      "-a pdf-themesdir=resources/themes",
      "-a pdf-fontsdir=resources/fonts",
      "-a allow-uri-read",
      "-o #{output_path}",
      temp_file
    ].join(' ')
    
    puts "🚀 Executing command: #{cmd}"
    
    # Выполняем команду
    result = system(cmd)
    
    if result
      puts "✅ Approval page generated: #{output_path}"
      true
    else
      puts "❌ Error generating approval page"
      false
    end
  end
  
end
