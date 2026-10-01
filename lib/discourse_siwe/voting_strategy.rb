# frozen_string_literal: true

module DiscourseSiwe
  module VotingStrategy
    # No predetermined weights: strategy rules are defined per proposal or community configuration
    DEFAULT_RULES = {}.freeze

    module_function

    def calculate_power(held_badges, rules = nil)
      active_rules = rules.is_a?(Hash) && !rules.empty? ? rules : DEFAULT_RULES

      badge_ids = parse_badge_ids(held_badges)
      return 0.0 if badge_ids.empty?

      total_power = 0.0

      badge_ids.each do |badge_id|
        str_id = badge_id.to_s
        weight = active_rules[str_id] || active_rules[str_id.to_i] || active_rules['*']
        total_power += weight.to_f if weight
      end

      total_power
    end

    def parse_badge_ids(held_badges)
      case held_badges
      when Array
        held_badges.map do |b|
          b.is_a?(Hash) ? (b['id'] || b[:id]).to_s : b.to_s
        end.reject(&:empty?).uniq
      when String
        held_badges.split(',').map(&:strip).reject(&:empty?).uniq
      else
        []
      end
    end

    def initialize_tallies(options)
      (options || []).each_with_index.map do |opt, idx|
        {
          index: idx,
          label: opt.to_s,
          vote_count: 0,
          voting_power: 0.0,
          percentage: 0.0,
        }
      end
    end

    def tally(options, votes, voting_type = :single_choice)
      case voting_type.to_s
      when 'weighted'
        tally_weighted(options, votes)
      when 'quadratic'
        tally_quadratic(options, votes)
      when 'approval'
        tally_approval(options, votes)
      else
        tally_single_choice(options, votes)
      end
    end

    # Single-choice voting: 100% of voting power goes to the chosen option
    def tally_single_choice(options, votes)
      tallies = initialize_tallies(options)
      total_power = 0.0

      (votes || []).each do |vote|
        choices = parse_choice_indices(vote.choice)
        power = vote.voting_power.to_f
        total_power += power

        if choices.any?
          idx = choices.first
          if idx >= 0 && idx < tallies.length
            tallies[idx][:vote_count] += 1
            tallies[idx][:voting_power] += power
          end
        end
      end

      finalize_percentages(tallies, total_power, (votes || []).size)
    end

    # Weighted voting: voter distributes weights across options (e.g. { "0": 50, "1": 30, "2": 20 })
    def tally_weighted(options, votes)
      tallies = initialize_tallies(options)
      total_power = 0.0

      (votes || []).each do |vote|
        power = vote.voting_power.to_f
        total_power += power
        weights = parse_choice_weights(vote.choice, tallies.length)

        sum_weights = weights.values.sum.to_f
        next if sum_weights <= 0

        weights.each do |idx, w|
          next if idx < 0 || idx >= tallies.length || w <= 0

          fraction = w.to_f / sum_weights
          allocated_power = power * fraction

          tallies[idx][:voting_power] += allocated_power
          tallies[idx][:vote_count] += 1
        end
      end

      finalize_percentages(tallies, total_power, (votes || []).size)
    end

    # Quadratic voting: effective weight per choice scales as sqrt(power allocated)
    def tally_quadratic(options, votes)
      tallies = initialize_tallies(options)
      total_effective_power = 0.0

      (votes || []).each do |vote|
        power = vote.voting_power.to_f
        weights = parse_choice_weights(vote.choice, tallies.length)

        sum_weights = weights.values.sum.to_f
        if sum_weights > 0
          weights.each do |idx, w|
            next if idx < 0 || idx >= tallies.length || w <= 0

            fraction = w.to_f / sum_weights
            allocated_power = power * fraction
            effective_power = Math.sqrt(allocated_power)

            tallies[idx][:voting_power] += effective_power
            tallies[idx][:vote_count] += 1
            total_effective_power += effective_power
          end
        else
          # Fallback single index
          choices = parse_choice_indices(vote.choice)
          if choices.any?
            idx = choices.first
            if idx >= 0 && idx < tallies.length
              effective_power = Math.sqrt(power)
              tallies[idx][:voting_power] += effective_power
              tallies[idx][:vote_count] += 1
              total_effective_power += effective_power
            end
          end
        end
      end

      finalize_percentages(tallies, total_effective_power, (votes || []).size)
    end

    # Approval voting: voter selects any number of acceptable options; each receives 100% of their power
    def tally_approval(options, votes)
      tallies = initialize_tallies(options)
      total_allocated_power = 0.0

      (votes || []).each do |vote|
        power = vote.voting_power.to_f
        choices = parse_choice_indices(vote.choice)

        choices.uniq.each do |idx|
          if idx >= 0 && idx < tallies.length
            tallies[idx][:voting_power] += power
            tallies[idx][:vote_count] += 1
            total_allocated_power += power
          end
        end
      end

      finalize_percentages(tallies, total_allocated_power, (votes || []).size)
    end

    def parse_choice_indices(choice)
      case choice
      when Array
        choice.map(&:to_i)
      when Integer, String
        # Could be JSON string or plain int string
        if choice.is_a?(String) && choice.start_with?('[')
          JSON.parse(choice).map(&:to_i) rescue [choice.to_i]
        else
          [choice.to_i]
        end
      else
        []
      end
    end

    def parse_choice_weights(choice, max_options)
      case choice
      when Hash
        choice.transform_keys(&:to_i).transform_values(&:to_f)
      when String
        if choice.start_with?('{')
          begin
            parsed = JSON.parse(choice)
            parsed.is_a?(Hash) ? parsed.transform_keys(&:to_i).transform_values(&:to_f) : {}
          rescue StandardError
            {}
          end
        else
          indices = parse_choice_indices(choice)
          indices.each_with_object({}) { |idx, h| h[idx] = 1.0 }
        end
      when Array
        # If array of indices, give equal weight
        choice.each_with_object({}) { |idx, h| h[idx.to_i] = 1.0 }
      else
        {}
      end
    end

    def finalize_percentages(tallies, total_power, total_votes_count)
      if total_power > 0
        tallies.each do |item|
          item[:percentage] = ((item[:voting_power] / total_power) * 100.0).round(2)
          item[:voting_power] = item[:voting_power].round(4)
        end
      end

      {
        total_votes: total_votes_count,
        total_power: total_power.round(4),
        tallies: tallies,
      }
    end
  end
end
