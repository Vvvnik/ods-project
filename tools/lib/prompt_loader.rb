#!/usr/bin/env ruby
# frozen_string_literal: true

require 'erb'

class PromptLoader
  def initialize(prompts_dir = nil, prompt_template = 'database_translations')
    @prompts_dir = prompts_dir || File.join(File.dirname(__dir__), 'prompts')
    @prompt_template = prompt_template
  end

  def load_prompt(template_name, variables = {})
    prompt_file = File.join(@prompts_dir, "#{template_name}.prompt")
    
    unless File.exist?(prompt_file)
      raise "Prompt template not found: #{prompt_file}"
    end

    template = File.read(prompt_file, encoding: 'utf-8')
    
    # Используем ERB для подстановки переменных
    erb = ERB.new(template)
    
    # Создаем контекст с переменными
    context = binding
    variables.each do |key, value|
      context.local_variable_set(key, value)
    end
    
    erb.result(context)
  end

end
