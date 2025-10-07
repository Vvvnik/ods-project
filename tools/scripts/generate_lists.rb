#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

# Простой запускающий скрипт для генерации списков
require_relative '../lib/list_generator'

puts "🚀 Генератор списков файлов для Antora"
puts "=" * 50

begin
  generator = ListGenerator.new
  generator.generate_all_components
rescue => e
  puts "❌ Ошибка: #{e.message}"
  puts e.backtrace.join("\n")
  exit 1
end

