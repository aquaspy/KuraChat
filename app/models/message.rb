class Message < ApplicationRecord
  ROLES = %w[user assistant system tool].freeze
  STATUSES = %w[pending streaming complete failed].freeze

  belongs_to :conversation, touch: true
  attribute :web, :boolean, default: false

  validates :role, inclusion: { in: ROLES }
  validates :content, length: { maximum: 16_384 }, if: -> { role == "user" }
  validate :user_content_present

  scope :chronological, -> { order(:id) }
  scope :transcript, -> {
    where(role: "user").or(
      where(role: "assistant", status: %w[pending streaming failed])
    ).or(
      where(role: "assistant", status: "complete").where.not(content: [ nil, "" ])
    )
  }

  def visible_in_ui?
    return true if role == "user"
    return false unless role == "assistant"
    return true if status.in?(%w[pending streaming failed])

    status == "complete" && content.present?
  end

  def inflight?
    role == "assistant" && status.in?(%w[pending streaming])
  end

  def failed?
    role == "assistant" && status == "failed"
  end

  def tool_calls?
    raw.is_a?(Hash) && raw["tool_calls"].present?
  end

  def as_openai(compact_tools_before: nil)
    return nil if role == "assistant" && status.in?(%w[pending streaming failed])
    return nil if role == "assistant" && content.blank? && !tool_calls?

    if tool_calls?
      { role: "assistant", content: nil, tool_calls: raw["tool_calls"] }
    elsif role == "tool"
      id = raw.is_a?(Hash) ? raw["tool_call_id"] : nil
      return nil if id.blank?

      body = content.to_s
      body = self.class.compact_tool_json(body) if compact_tools_before && self.id < compact_tools_before
      { role: "tool", tool_call_id: id, content: body }
    else
      { role: role, content: content.to_s }
    end
  end

  def self.compact_tool_json(json)
    data = JSON.parse(json)
    results = Array(data["results"]).map { |row| { "title" => row["title"], "url" => row["url"] } }
    out = { "query" => data["query"], "results" => results }
    out["error"] = data["error"] if data["error"]
    JSON.generate(out)
  rescue JSON::ParserError
    json.to_s.truncate(400)
  end

  private
    def user_content_present
      return unless role == "user"
      errors.add(:content, :blank) if content.to_s.strip.blank?
    end
end
