# frozen_string_literal: true

class SpProposal < ActiveRecord::Base
  self.table_name = 'sp_proposals'

  has_many :sp_votes, dependent: :destroy

  enum status: { open: 0, closed: 1 }
  enum voting_type: { single_choice: 0, weighted: 1, quadratic: 2, approval: 3 }

  validates :topic_id, presence: true, uniqueness: true
  validates :title, presence: true
  validates :snapshot_block, presence: true, numericality: { greater_than: 0 }
  validates :ends_at, presence: true

  def active?
    open? && Time.now.utc < ends_at
  end

  def tally_results(mask_shielded: true)
    parsed_options = options.is_a?(Array) ? options : []

    if mask_shielded && respond_to?(:shielded) && shielded? && active?
      tally = parsed_options.each_with_index.map do |opt, idx|
        {
          index: idx,
          label: opt.to_s,
          vote_count: nil,
          voting_power: nil,
          percentage: nil,
        }
      end

      return {
        is_shielded: true,
        total_votes: sp_votes.count,
        total_power: nil,
        tallies: tally,
      }
    end

    raw_tally = DiscourseSiwe::VotingStrategy.tally(
      parsed_options,
      sp_votes.to_a,
      respond_to?(:voting_type) ? (voting_type || :single_choice) : :single_choice
    )

    raw_tally.merge(is_shielded: false)
  end

  def winning_option
    res = tally_results(mask_shielded: false)
    return nil if res[:tallies].blank?

    res[:tallies].max_by { |t| t[:voting_power] }
  end

  def safe_transaction_payload
    return nil unless respond_to?(:execution_payload) && execution_payload.present?
    return nil if active?

    winner = winning_option
    # Passed if winning option is index 0 ("Approve" / top choice) and power > 0
    return nil unless winner && winner[:index] == 0 && winner[:voting_power].to_f > 0

    {
      version: '1.0',
      chainId: SiteSetting.siwe_voting_chain_id.to_s,
      createdAt: Time.now.utc.to_i,
      meta: {
        name: "Execution for Proposal ##{topic_id}: #{title}",
        description: "Passed governance vote on topic #{topic_id}",
      },
      transactions: [
        {
          to: execution_payload['to'],
          value: execution_payload['value'] || '0',
          data: execution_payload['data'] || '0x',
          operation: execution_payload['operation'] || 0,
        },
      ],
    }
  end
end
