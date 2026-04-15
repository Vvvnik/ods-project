#!/usr/bin/env ruby
# frozen_string_literal: true

# Выгрузка текста задачи Jira в Markdown по настройкам tools/config.yml → defaults.jira
#
# Использование (из корня репозитория):
#   ruby tools/scripts/jira_issue_to_md.rb
#     — все ключи из defaults.jira.main_issues_file (по одному в строке)
#   ruby tools/scripts/jira_issue_to_md.rb ODS-42
#     — только одна задача (и её подзадачи в папку ODS-42/)
#
# Jira Cloud: задайте email учётной записи Atlassian в config (jira.email) или в JIRA_EMAIL.

require 'base64'
require 'cgi'
require 'fileutils'
require 'json'
require 'net/http'
require 'uri'
require 'yaml'

ROOT = File.expand_path('../..', __dir__)
CONFIG_PATH = File.join(ROOT, 'tools', 'config.yml')

def load_jira_config
  unless File.file?(CONFIG_PATH)
    warn "Нет файла конфигурации: #{CONFIG_PATH}"
    exit 1
  end
  cfg = YAML.safe_load(File.read(CONFIG_PATH, encoding: 'utf-8'), aliases: true)
  jira = cfg.dig('defaults', 'jira')
  unless jira.is_a?(Hash)
    warn 'В config.yml не найден блок defaults.jira'
    exit 1
  end
  jira
end

def basic_auth_header(email, api_token)
  token = api_token.to_s.strip
  raise 'Пустой api_token (config jira.api_token или JIRA_API_TOKEN)' if token.empty?

  enc = Base64.strict_encode64("#{email}:#{token}")
  "Basic #{enc}"
end

def jira_get_json(base_url, path, auth_header)
  uri = URI("#{base_url.chomp('/')}/#{path.sub(%r{\A/}, '')}")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = (uri.scheme == 'https')
  http.open_timeout = 30
  http.read_timeout = 120
  req = Net::HTTP::Get.new(uri)
  req['Accept'] = 'application/json'
  req['Authorization'] = auth_header

  res = http.request(req)
  [res.code, res.body]
end

def fetch_issue(base_url, auth_header, issue_key, fields)
  issue_path = URI.encode_www_form_component(issue_key)
  query = URI.encode_www_form('expand' => 'renderedFields', 'fields' => fields)
  path = "rest/api/3/issue/#{issue_path}?#{query}"
  code, body = jira_get_json(base_url, path, auth_header)
  return [nil, "Jira API HTTP #{code}: #{body[0, 2000]}"] unless code == '200'

  [JSON.parse(body), nil]
end

def simple_html_to_markdown(html)
  return '' if html.nil? || html.strip.empty?

  h = html.dup
  h.gsub!(%r{<a\s+[^>]*href=["']([^"']+)["'][^>]*>(.*?)</a>}im) do
    inner = Regexp.last_match(2).gsub(%r{<[^>]+>}, '')
    "[#{inner.strip}](#{Regexp.last_match(1)})"
  end
  h.gsub!(%r{<br\s*/?>}i, "\n")
  h.gsub!(%r{</p>}i, "\n\n")
  h.gsub!(%r{<li[^>]*>}i, "\n- ")
  h.gsub!(%r{</li>}i, '')
  h.gsub!(%r{<h([1-6])[^>]*>(.*?)</h\1>}im) do
    level = Regexp.last_match(1).to_i
    text = Regexp.last_match(2).gsub(%r{<[^>]+>}, '').strip
    "\n#{'#' * level} #{text}\n\n"
  end
  h.gsub!(%r{<[^>]+>}, '')
  CGI.unescapeHTML(h.gsub(/\n{3,}/, "\n\n").strip)
end

def adf_to_md(node)
  return '' unless node.is_a?(Hash)

  case node['type']
  when 'doc'
    (node['content'] || []).map { |c| adf_to_md(c) }.join
  when 'paragraph'
    (node['content'] || []).map { |c| adf_to_md(c) }.join + "\n\n"
  when 'text'
    t = node['text'].to_s
    (node['marks'] || []).each do |m|
      case m['type']
      when 'strong' then t = "**#{t}**"
      when 'em' then t = "_#{t}_"
      when 'code' then t = "`#{t}`"
      when 'link'
        href = m.dig('attrs', 'href').to_s
        t = "[#{t}](#{href})" unless href.empty?
      end
    end
    t
  when 'heading'
    level = (node.dig('attrs', 'level') || 1).to_i
    text = (node['content'] || []).map { |c| adf_to_md(c) }.join
    "#{'#' * level} #{text}\n\n"
  when 'bulletList'
    (node['content'] || []).map { |c| adf_to_md(c) }.join
  when 'orderedList'
    (node['content'] || []).each_with_index.map { |c, i| adf_ordered_item(c, i + 1) }.join
  when 'listItem'
    body = (node['content'] || []).map { |c| adf_to_md(c) }.join.strip
    indent = body.include?("\n") ? body.gsub("\n", "\n  ") : body
    "- #{indent}\n"
  when 'hardBreak'
    "\n"
  when 'codeBlock'
    lang = node.dig('attrs', 'language').to_s
    lines = (node['content'] || []).map { |c| c['text'] }.compact.join
    fence = '```'
    "#{fence}#{lang}\n#{lines}#{fence}\n\n"
  when 'blockquote'
    inner = (node['content'] || []).map { |c| adf_to_md(c) }.join.strip
    inner.split("\n").map { |ln| "> #{ln}" }.join("\n") + "\n\n"
  else
    (node['content'] || []).map { |c| adf_to_md(c) }.join
  end
end

def adf_ordered_item(node, index)
  return '' unless node.is_a?(Hash) && node['type'] == 'listItem'

  body = (node['content'] || []).map { |c| adf_to_md(c) }.join.strip
  indent = body.include?("\n") ? body.gsub("\n", "\n   ") : body
  "#{index}. #{indent}\n"
end

def description_to_markdown(fields, rendered_fields)
  html = rendered_fields && rendered_fields['description']
  return simple_html_to_markdown(html) if html.is_a?(String) && !html.strip.empty?

  desc = fields['description']
  return '' if desc.nil?
  return desc if desc.is_a?(String)

  adf_to_md(desc) if desc.is_a?(Hash)
end

def issue_reference_md(issue, base_url)
  return '' unless issue.is_a?(Hash)

  key = issue['key'].to_s
  return '' if key.empty?

  f = issue['fields'] || {}
  summary = f.dig('summary').to_s
  status = f.dig('status', 'name').to_s
  base = base_url.to_s.strip.chomp('/')
  key_part =
    if base.empty?
      "**#{key}**"
    else
      u = "#{base}/browse/#{key}"
      "[**#{key}**](#{u})"
    end
  extras = [summary, status].reject(&:empty?)
  extras.empty? ? key_part : "#{key_part}: #{extras.join(' — ')}"
end

def subtasks_to_markdown(fields, base_url)
  list = fields['subtasks']
  return [] unless list.is_a?(Array)

  list.filter_map do |st|
    next unless st.is_a?(Hash)

    ref = issue_reference_md(st, base_url)
    next if ref.empty?

    "- #{ref}"
  end
end

def issue_links_to_markdown(fields, base_url)
  links = fields['issuelinks']
  return [] unless links.is_a?(Array)

  links.filter_map do |link|
    next unless link.is_a?(Hash)

    type = link['type'] || {}
    issue, phrase =
      if link['outwardIssue'].is_a?(Hash)
        [link['outwardIssue'], type['outward'].to_s]
      elsif link['inwardIssue'].is_a?(Hash)
        [link['inwardIssue'], type['inward'].to_s]
      else
        next
      end
    phrase = type['name'].to_s if phrase.empty?
    ref = issue_reference_md(issue, base_url)
    next if ref.empty?

    "- **#{phrase}** — #{ref}"
  end
end

def issue_to_markdown(data, base_url: '')
  fields = data['fields'] || {}
  rendered = data['renderedFields']
  key = data['key']
  summary = fields.dig('summary').to_s
  status = fields.dig('status', 'name').to_s
  issuetype = fields.dig('issuetype', 'name').to_s
  priority = fields.dig('priority', 'name').to_s
  assignee = fields.dig('assignee', 'displayName').to_s
  reporter = fields.dig('reporter', 'displayName').to_s
  created = fields['created'].to_s
  updated = fields['updated'].to_s

  body_md = description_to_markdown(fields, rendered).to_s.strip

  lines = []
  lines << "# #{key}: #{summary}"
  lines << ''
  lines << "| Поле | Значение |"
  lines << "| --- | --- |"
  lines << "| Тип | #{issuetype} |" unless issuetype.empty?
  lines << "| Статус | #{status} |" unless status.empty?
  lines << "| Приоритет | #{priority} |" unless priority.empty?
  lines << "| Исполнитель | #{assignee} |" unless assignee.empty?
  lines << "| Автор | #{reporter} |" unless reporter.empty?
  lines << "| Создано | #{created} |" unless created.empty?
  lines << "| Обновлено | #{updated} |" unless updated.empty?
  lines << ''
  lines << '## Описание'
  lines << ''
  lines << (body_md.empty? ? '_Нет описания._' : body_md)
  lines << ''
  lines << '## Подзадачи'
  lines << ''
  sub_md = subtasks_to_markdown(fields, base_url)
  lines << (sub_md.empty? ? '_Нет подзадач._' : sub_md.join("\n"))
  lines << ''
  lines << '## Привязанные задачи'
  lines << ''
  link_md = issue_links_to_markdown(fields, base_url)
  lines << (link_md.empty? ? '_Нет привязанных задач._' : link_md.join("\n"))
  lines << ''
  lines.join("\n")
end

def parse_main_issues_file(path)
  File.readlines(path, encoding: 'utf-8').filter_map do |line|
    s = line.strip
    next if s.empty? || s.start_with?('#')

    s
  end
end

def main_issue_keys(jira)
  arg = ARGV[0].to_s.strip
  return [arg] unless arg.empty?

  rel = jira['main_issues_file'].to_s.strip
  if rel.empty?
    warn 'Укажите defaults.jira.main_issues_file или передайте ключ задачи первым аргументом'
    exit 1
  end

  abs = File.expand_path(rel, ROOT)
  unless File.file?(abs)
    warn "Файл со списком задач не найден: #{abs}"
    exit 1
  end

  keys = parse_main_issues_file(abs)
  if keys.empty?
    warn "В #{abs} нет ни одного ключа задачи (непустые строки без #)"
    exit 1
  end

  keys.uniq
end

def export_main_issue_with_subtasks(base_url, auth, fields, main_key, dst_rel)
  data, error = fetch_issue(base_url, auth, main_key, fields)
  unless error.nil?
    warn "Задача #{main_key}: #{error}"
    return
  end

  root_out_dir = File.expand_path(dst_rel, ROOT)
  out_dir = File.join(root_out_dir, main_key)
  FileUtils.mkdir_p(out_dir)

  root_key = (data['key'] || main_key).to_s
  root_file = File.join(out_dir, "#{root_key}.md")
  File.write(root_file, issue_to_markdown(data, base_url: base_url), encoding: 'utf-8')
  puts "Записано: #{root_file}"

  subtasks = data.dig('fields', 'subtasks')
  return unless subtasks.is_a?(Array)

  subtasks.each do |st|
    next unless st.is_a?(Hash)

    sub_key = st['key'].to_s.strip
    next if sub_key.empty?

    sub_data, sub_error = fetch_issue(base_url, auth, sub_key, fields)
    if sub_error
      warn "Не удалось загрузить подзадачу #{sub_key}: #{sub_error}"
      next
    end

    sub_file = File.join(out_dir, "#{sub_key}.md")
    File.write(sub_file, issue_to_markdown(sub_data, base_url: base_url), encoding: 'utf-8')
    puts "Записано: #{sub_file}"
  end
end

# --- main ---
jira = load_jira_config
base_url = jira['url'].to_s.strip
dst_rel = jira['dst'].to_s.strip

if base_url.empty? || dst_rel.empty?
  warn 'Заполните в config defaults.jira: url, dst'
  exit 1
end

email = (ENV['JIRA_EMAIL'] || jira['email']).to_s.strip
if email.empty?
  warn 'Нужен email для Jira Cloud API: укажите defaults.jira.email в tools/config.yml или переменную JIRA_EMAIL'
  exit 1
end

api_token = ENV['JIRA_API_TOKEN']&.strip
api_token = jira['api_token'].to_s.strip if api_token.nil? || api_token.empty?

auth = basic_auth_header(email, api_token)
fields = 'summary,description,status,issuetype,priority,assignee,reporter,created,updated,subtasks,issuelinks'

main_issue_keys(jira).each do |issue_key|
  export_main_issue_with_subtasks(base_url, auth, fields, issue_key, dst_rel)
end
