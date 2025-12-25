#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'digest'

# Линтер AsciiDoc на базе CLI asciidoctor:
# - НЕ генерирует выходные файлы (использует -o /dev/null)
# - Пишет stderr (WARN/ERROR и т.п.) в лог по компоненту
# - Не валит сборку: ошибки фиксируются только в логах и итоговой сводке
module AsciidocLinter
  Result = Struct.new(
    :component,
    :ran,
    :asciidoctor_available,
    :files_scanned,
    :files_with_messages,
    :warnings,
    :errors,
    :log_path,
    :log_updated,
    keyword_init: true
  )

  def self.lint_component(comp, defaults)
    cfg = (comp['asciidoctor_lint'] || defaults.dig('defaults', 'asciidoctor_lint') || {})
    return Result.new(component: comp['name'], ran: false, asciidoctor_available: true, files_scanned: 0, files_with_messages: 0, warnings: 0, errors: 0, log_path: nil, log_updated: false) unless cfg['enabled']

    name = comp['name']
    src_root = (cfg['src'] || "components/{name}").gsub('{name}', name)
    log_path = (cfg['log'] || "components/{name}/asciidoctor-lint.log").gsub('{name}', name)

    before_hash = File.exist?(log_path) ? Digest::SHA256.hexdigest(File.read(log_path, encoding: 'UTF-8')) : nil
    FileUtils.mkdir_p(File.dirname(log_path))
    File.write(log_path, '', encoding: 'UTF-8')

    asciidoctor_ok = asciidoctor_available?
    unless asciidoctor_ok
      File.write(log_path, "asciidoctor CLI не найден в PATH. Установите asciidoctor (gem install asciidoctor) или добавьте в PATH.\n", encoding: 'UTF-8')
      after_hash = Digest::SHA256.hexdigest(File.read(log_path, encoding: 'UTF-8'))
      return Result.new(
        component: name,
        ran: true,
        asciidoctor_available: false,
        files_scanned: 0,
        files_with_messages: 0,
        warnings: 0,
        errors: 0,
        log_path: log_path,
        log_updated: before_hash && before_hash != after_hash
      )
    end

    adoc_files = Dir.glob(File.join(src_root, '**', '*.adoc'))
    files_scanned = adoc_files.length

    files_with_messages = 0
    warn_count = 0
    error_count = 0

    # Для простого lint не подключаем расширения (kroki и т.п.), только чистый asciidoctor.
    # Параметры ниже остаются только как конфиг-комментарии, чтобы можно было ужесточить при желании.
    # failure_level = cfg['failure_level'] # ERROR|WARN|INFO|DEBUG
    # attributes = cfg['attributes'] || {}

    adoc_files.each do |file|
      # -o File::NULL => ничего не генерируем, только парсим документ
      cmd = ['asciidoctor', '-o', File::NULL, file]
      _out, err, _status = Open3.capture3(*cmd)

      next if err.nil? || err.strip.empty?

      files_with_messages += 1
      warn_count += err.scan(/:\s*WARNING:/i).length
      error_count += err.scan(/:\s*ERROR:/i).length

      File.open(log_path, 'a', encoding: 'UTF-8') do |f|
        f.puts "=== #{file} ==="
        f.puts err.rstrip
        f.puts
      end
    end

    after_hash = Digest::SHA256.hexdigest(File.read(log_path, encoding: 'UTF-8'))

    Result.new(
      component: name,
      ran: true,
      asciidoctor_available: true,
      files_scanned: files_scanned,
      files_with_messages: files_with_messages,
      warnings: warn_count,
      errors: error_count,
      log_path: log_path,
      log_updated: before_hash && before_hash != after_hash
    )
  end

  def self.asciidoctor_available?
    _out, _err, status = Open3.capture3('asciidoctor', '-V')
    status.success?
  rescue Errno::ENOENT
    false
  end
end


