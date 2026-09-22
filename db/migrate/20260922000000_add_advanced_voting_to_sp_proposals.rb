# frozen_string_literal: true

class AddAdvancedVotingToSpProposals < ActiveRecord::Migration[7.0]
  def change
    add_column :sp_proposals, :voting_type, :integer, default: 0, null: false
    add_column :sp_proposals, :quorum, :decimal, precision: 30, scale: 0, default: 0
    add_column :sp_proposals, :execution_payload, :jsonb, default: nil
  end
end
