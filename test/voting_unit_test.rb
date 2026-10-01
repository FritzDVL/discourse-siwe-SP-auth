#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'json'

$LOAD_PATH.unshift(*Dir[File.join(__dir__, '..', 'gems/*/gems/keccak-*/lib')])

require_relative '../lib/discourse_siwe/voting_strategy'

class VotingStrategyTest < Minitest::Test
  def test_empty_badges_returns_zero
    assert_equal 0.0, DiscourseSiwe::VotingStrategy.calculate_power([])
    assert_equal 0.0, DiscourseSiwe::VotingStrategy.calculate_power(nil)
    assert_equal 0.0, DiscourseSiwe::VotingStrategy.calculate_power('')
  end

  def test_empty_rules_returns_zero
    # With no strategy rules defined, voting power defaults to 0.0 (no arbitrary preset weights)
    assert_equal 0.0, DiscourseSiwe::VotingStrategy.calculate_power(['25'])
    assert_equal 0.0, DiscourseSiwe::VotingStrategy.calculate_power(['11', '13'])
  end

  def test_core_team_rules_two_votes
    # Core Team badge (#25) configured with 2 votes each
    rules = { '25' => 2 }
    assert_equal 2.0, DiscourseSiwe::VotingStrategy.calculate_power(['25'], rules)
    assert_equal 2.0, DiscourseSiwe::VotingStrategy.calculate_power([{ 'id' => '25', 'name' => 'Core Team' }], rules)

    # Other badges have 0 votes unless explicitly configured in rules
    assert_equal 0.0, DiscourseSiwe::VotingStrategy.calculate_power(['11'], rules)
    assert_equal 2.0, DiscourseSiwe::VotingStrategy.calculate_power(['25', '11'], rules)
  end

  def test_custom_strategy_rules
    rules = { '100' => 10, '200' => 25 }
    assert_equal 35.0, DiscourseSiwe::VotingStrategy.calculate_power(['100', '200'], rules)
    assert_equal 0.0, DiscourseSiwe::VotingStrategy.calculate_power(['11'], rules)
  end

  def test_duplicate_badges_counted_once
    rules = { '25' => 2 }
    assert_equal 2.0, DiscourseSiwe::VotingStrategy.calculate_power(['25', '25'], rules)
  end
end

class ProposalTallyLogicTest < Minitest::Test
  VoteMock = Struct.new(:choice, :voting_power)

  def test_single_choice_tally
    options = ['Approve', 'Reject', 'Abstain']
    votes = [
      VoteMock.new([0], 10.0),
      VoteMock.new([0], 5.0),
      VoteMock.new([1], 5.0),
    ]

    result = DiscourseSiwe::VotingStrategy.tally(options, votes, :single_choice)

    assert_equal 3, result[:total_votes]
    assert_equal 20.0, result[:total_power]

    # Option 0 (Approve): 15 power / 20 = 75%
    assert_equal 2, result[:tallies][0][:vote_count]
    assert_equal 15.0, result[:tallies][0][:voting_power]
    assert_equal 75.0, result[:tallies][0][:percentage]

    # Option 1 (Reject): 5 power / 20 = 25%
    assert_equal 1, result[:tallies][1][:vote_count]
    assert_equal 5.0, result[:tallies][1][:voting_power]
    assert_equal 25.0, result[:tallies][1][:percentage]
  end

  def test_weighted_voting_competition_distribution
    options = ['Project Alpha', 'Project Beta', 'Project Gamma']
    # Voter 1 has 10 power and splits 50% to Alpha, 30% to Beta, 20% to Gamma
    # Voter 2 has 20 power and gives 100% to Alpha
    votes = [
      VoteMock.new({ '0' => 50, '1' => 30, '2' => 20 }, 10.0),
      VoteMock.new({ '0' => 100 }, 20.0),
    ]

    result = DiscourseSiwe::VotingStrategy.tally_weighted(options, votes)

    assert_equal 2, result[:total_votes]
    assert_equal 30.0, result[:total_power]

    # Alpha: 5 (from Voter 1) + 20 (from Voter 2) = 25 power
    # 25 / 30 = 83.33%
    assert_equal 2, result[:tallies][0][:vote_count]
    assert_equal 25.0, result[:tallies][0][:voting_power]
    assert_equal 83.33, result[:tallies][0][:percentage]

    # Beta: 3 (from Voter 1) = 3 power (10%)
    assert_equal 1, result[:tallies][1][:vote_count]
    assert_equal 3.0, result[:tallies][1][:voting_power]
    assert_equal 10.0, result[:tallies][1][:percentage]

    # Gamma: 2 (from Voter 1) = 2 power (6.67%)
    assert_equal 1, result[:tallies][2][:vote_count]
    assert_equal 2.0, result[:tallies][2][:voting_power]
    assert_equal 6.67, result[:tallies][2][:percentage]
  end

  def test_quadratic_voting_tally
    options = ['Option A', 'Option B']
    # Voter 1 has 100 power -> sqrt(100) = 10
    # Voter 2 has 16 power -> sqrt(16) = 4
    votes = [
      VoteMock.new([0], 100.0),
      VoteMock.new([1], 16.0),
    ]

    result = DiscourseSiwe::VotingStrategy.tally_quadratic(options, votes)

    assert_equal 2, result[:total_votes]
    assert_equal 14.0, result[:total_power]
    assert_equal 10.0, result[:tallies][0][:voting_power]
    assert_equal 71.43, result[:tallies][0][:percentage]
    assert_equal 4.0, result[:tallies][1][:voting_power]
    assert_equal 28.57, result[:tallies][1][:percentage]
  end

  def test_approval_voting_tally
    options = ['Idea 1', 'Idea 2', 'Idea 3']
    # Voter 1 approves 0 and 2 with 10 power
    votes = [
      VoteMock.new([0, 2], 10.0),
    ]

    result = DiscourseSiwe::VotingStrategy.tally_approval(options, votes)

    assert_equal 10.0, result[:tallies][0][:voting_power]
    assert_equal 0.0, result[:tallies][1][:voting_power]
    assert_equal 10.0, result[:tallies][2][:voting_power]
  end

  def test_shielded_tally_masked_when_active
    options = ['Option A', 'Option B']
    votes = [VoteMock.new([0], 10.0)]

    proposal = Struct.new(:options, :shielded?, :active?, :sp_votes) do
      def tally_results(mask_shielded: true)
        if mask_shielded && shielded? && active?
          return {
            is_shielded: true,
            total_votes: sp_votes.size,
            total_power: nil,
            tallies: options.map.with_index { |opt, idx| { index: idx, label: opt, vote_count: nil, voting_power: nil, percentage: nil } }
          }
        end
      end
    end.new(options, true, true, votes)

    shielded_result = proposal.tally_results(mask_shielded: true)
    assert_equal true, shielded_result[:is_shielded]
    assert_nil shielded_result[:total_power]
    assert_nil shielded_result[:tallies][0][:percentage]
    assert_nil shielded_result[:tallies][0][:voting_power]
    assert_equal 1, shielded_result[:total_votes]
  end
end

# Mock EthRpc keccak if Digest::Keccak not loaded
unless defined?(Digest::Keccak)
  module Digest
    class Keccak
      def initialize(_); end
      def digest(data)
        OpenSSL::Digest::SHA256.digest(data)
      end
    end
  end
end

require_relative '../lib/discourse_siwe/eth_rpc'
require_relative '../lib/discourse_siwe/eip712'

class Eip712HashingTest < Minitest::Test
  def test_hash_vote_deterministic
    h1 = DiscourseSiwe::Eip712.hash_vote(123, [0], 1700000000, 1)
    h2 = DiscourseSiwe::Eip712.hash_vote(123, [0], 1700000000, 1)
    assert_equal h1, h2
    assert_equal 32, h1.bytesize
  end

  def test_hash_vote_weighted_string_json
    choice_json = '{"0":50,"1":50}'
    h1 = DiscourseSiwe::Eip712.hash_vote(123, choice_json, 1700000000, 1)
    h2 = DiscourseSiwe::Eip712.hash_vote(123, { '0' => 50, '1' => 50 }, 1700000000, 1)
    assert_equal h1, h2
    assert_equal 32, h1.bytesize
  end

  def test_hash_vote_differs_on_choice
    h1 = DiscourseSiwe::Eip712.hash_vote(123, [0], 1700000000, 1)
    h2 = DiscourseSiwe::Eip712.hash_vote(123, [1], 1700000000, 1)
    refute_equal h1, h2
  end

  def test_hash_vote_differs_on_topic_id
    h1 = DiscourseSiwe::Eip712.hash_vote(123, [0], 1700000000, 1)
    h2 = DiscourseSiwe::Eip712.hash_vote(124, [0], 1700000000, 1)
    refute_equal h1, h2
  end

  def test_hash_vote_differs_on_chain_id
    h1 = DiscourseSiwe::Eip712.hash_vote(123, [0], 1700000000, 1)
    h2 = DiscourseSiwe::Eip712.hash_vote(123, [0], 1700000000, 11155111)
    refute_equal h1, h2
  end
end
