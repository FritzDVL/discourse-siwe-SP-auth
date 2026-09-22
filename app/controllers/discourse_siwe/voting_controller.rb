# frozen_string_literal: true

module DiscourseSiwe
  class VotingController < ::ApplicationController
    skip_before_action :check_xhr, only: %i[show]
    skip_before_action :redirect_to_login_if_required, only: %i[show]

    before_action :ensure_voting_enabled

    def show
      topic_id = params[:topic_id].to_i
      proposal = SpProposal.find_by(topic_id: topic_id)

      unless proposal
        return render json: { exists: false, proposal: nil }
      end

      tally = proposal.tally_results

      user_vote = nil
      user_power = 0.0
      user_wallet = nil

      if current_user
        user_wallet = current_user.custom_fields['wallet_address']&.downcase
        if user_wallet.present?
          v = SpVote.find_by(sp_proposal_id: proposal.id, voter_address: user_wallet)
          if v
            user_vote = {
              choice: v.choice,
              voting_power: v.voting_power.to_f,
              signed_at: v.signed_at,
            }
          end

          held_badges = DiscourseSiwe::IdentityResolver.resolve_badges_at_block(
            user_wallet,
            proposal.snapshot_block
          )
          user_power = DiscourseSiwe::VotingStrategy.calculate_power(
            held_badges,
            proposal.strategy_rules
          )
        end
      end

      render json: {
        exists: true,
        proposal: {
          id: proposal.id,
          topic_id: proposal.topic_id,
          title: proposal.title,
          options: proposal.options,
          snapshot_block: proposal.snapshot_block,
          ends_at: proposal.ends_at.iso8601,
          status: proposal.status,
          voting_type: proposal.respond_to?(:voting_type) ? (proposal.voting_type || 'single_choice') : 'single_choice',
          quorum: proposal.respond_to?(:quorum) ? proposal.quorum.to_f : 0.0,
          is_active: proposal.active?,
          shielded: proposal.respond_to?(:shielded) ? proposal.shielded : false,
          strategy_rules: proposal.strategy_rules,
          safe_payload: proposal.safe_transaction_payload,
        },
        tally: tally,
        user_vote: user_vote,
        user_power: user_power,
        user_wallet: user_wallet,
      }
    end

    def create_proposal
      raise Discourse::InvalidAccess unless current_user&.staff?

      topic_id = params[:topic_id].to_i
      title = params[:title].to_s.presence
      options = params[:options]
      ends_at = params[:ends_at]
      strategy_rules = params[:strategy_rules]
      snapshot_block = params[:snapshot_block].to_i
      shielded_param = params[:shielded]
      voting_type_param = params[:voting_type]
      quorum_param = params[:quorum].to_f
      execution_payload = params[:execution_payload]

      if topic_id <= 0
        return render json: { error: 'Invalid or missing topic_id' }, status: 400
      end

      unless options.is_a?(Array) && options.length >= 2
        return render json: { error: 'Proposal requires at least 2 options' }, status: 400
      end

      topic = Topic.find_by(id: topic_id)
      title ||= topic&.title || "Governance Proposal ##{topic_id}"

      parsed_ends_at = parse_ends_at(ends_at)
      unless parsed_ends_at && parsed_ends_at > Time.now.utc
        return render json: { error: 'Invalid ends_at timestamp (must be in the future)' }, status: 400
      end

      if snapshot_block <= 0
        snapshot_block = DiscourseSiwe::EthRpc.eth_block_number || 1
      end

      rules = strategy_rules.is_a?(Hash) ? strategy_rules : DiscourseSiwe::VotingStrategy::DEFAULT_RULES

      shielded = shielded_param.nil? ? SiteSetting.siwe_voting_shielded_default : (shielded_param == true || shielded_param == 'true')

      voting_type = case voting_type_param.to_s.downcase
                    when '1', 'weighted' then :weighted
                    when '2', 'quadratic' then :quadratic
                    when '3', 'approval' then :approval
                    else :single_choice
                    end

      proposal = SpProposal.find_or_initialize_by(topic_id: topic_id)
      proposal.assign_attributes(
        title: title,
        options: options.map(&:to_s),
        snapshot_block: snapshot_block,
        ends_at: parsed_ends_at,
        strategy_rules: rules,
        shielded: shielded,
        status: :open,
      )

      proposal.voting_type = voting_type if proposal.respond_to?(:voting_type=)
      proposal.quorum = quorum_param if proposal.respond_to?(:quorum=) && quorum_param > 0
      proposal.execution_payload = execution_payload if proposal.respond_to?(:execution_payload=) && execution_payload.is_a?(Hash)

      if proposal.save
        render json: { success: true, proposal: proposal }
      else
        render json: { error: proposal.errors.full_messages.join(', ') }, status: 422
      end
    end

    def cast_vote
      raise Discourse::NotLoggedIn unless current_user

      voter_wallet = current_user.custom_fields['wallet_address']&.downcase
      if voter_wallet.blank?
        return render json: { error: 'No verified Ethereum address linked to your account' }, status: 400
      end

      topic_id = params[:topic_id].to_i
      proposal = SpProposal.find_by(topic_id: topic_id)

      unless proposal
        return render json: { error: 'Proposal not found' }, status: 404
      end

      unless proposal.active?
        return render json: { error: 'Voting is closed for this proposal' }, status: 400
      end

      max_option_idx = proposal.options.length - 1
      choice_param = params[:choice]

      parsed_choice = normalize_choice(choice_param, proposal, max_option_idx)
      if parsed_choice.nil?
        return render json: { error: 'Invalid option selection or weight distribution' }, status: 400
      end

      signature = params[:signature].to_s.presence
      timestamp = params[:timestamp].to_i

      if signature.blank? || timestamp <= 0
        return render json: { error: 'Missing signature or timestamp' }, status: 400
      end

      # Enforce reasonable signature timestamp window (within 24 hours of current time)
      if (Time.now.utc.to_i - timestamp).abs > 86_400
        return render json: { error: 'Signature timestamp expired or invalid' }, status: 400
      end

      chain_id = SiteSetting.siwe_voting_chain_id.to_i
      chain_id = 1 if chain_id <= 0

      # Verify EIP-712 signature matching current user's SIWE wallet
      valid_signature = DiscourseSiwe::Eip712.verify_vote(
        voter_wallet,
        proposal.topic_id,
        parsed_choice,
        timestamp,
        signature,
        chain_id
      )

      unless valid_signature
        return render json: { error: 'Signature verification failed' }, status: 400
      end

      # Calculate voter's power at the snapshot block height
      held_badges = DiscourseSiwe::IdentityResolver.resolve_badges_at_block(
        voter_wallet,
        proposal.snapshot_block
      )
      voting_power = DiscourseSiwe::VotingStrategy.calculate_power(
        held_badges,
        proposal.strategy_rules
      )

      if voting_power <= 0
        return render json: {
          error: 'You do not hold eligible badges for voting at the proposal snapshot block'
        }, status: 403
      end

      # Upsert vote
      vote = SpVote.find_or_initialize_by(
        sp_proposal_id: proposal.id,
        topic_id: proposal.topic_id,
        voter_address: voter_wallet
      )

      vote.assign_attributes(
        choice: parsed_choice,
        voting_power: voting_power,
        signature: signature,
        signed_at: timestamp,
      )

      if vote.save
        render json: {
          success: true,
          voting_power: voting_power,
          choice: parsed_choice,
          tally: proposal.tally_results,
        }
      else
        render json: { error: vote.errors.full_messages.join(', ') }, status: 422
      end
    end

    private

    def ensure_voting_enabled
      raise Discourse::NotFound unless SiteSetting.siwe_voting_enabled
    end

    def parse_ends_at(raw)
      return nil if raw.blank?
      Time.parse(raw.to_s).utc
    rescue ArgumentError
      nil
    end

    def normalize_choice(choice_param, proposal, max_option_idx)
      is_weighted = proposal.respond_to?(:weighted?) && proposal.weighted?

      if is_weighted
        raw_hash = case choice_param
                   when Hash then choice_param
                   when String
                     begin
                       JSON.parse(choice_param)
                     rescue StandardError
                       nil
                     end
                   else nil
                   end

        return nil unless raw_hash.is_a?(Hash) && !raw_hash.empty?

        weights = {}
        raw_hash.each do |k, v|
          idx = k.to_i
          val = v.to_f
          return nil if idx < 0 || idx > max_option_idx || val < 0
          weights[idx.to_s] = val if val > 0
        end

        return nil if weights.empty? || weights.values.sum <= 0
        weights
      else
        choice_array = case choice_param
                       when Array then choice_param.map(&:to_i)
                       when Integer, String
                         if choice_param.is_a?(String) && choice_param.start_with?('[')
                           JSON.parse(choice_param).map(&:to_i) rescue [choice_param.to_i]
                         else
                           [choice_param.to_i]
                         end
                       else nil
                       end

        return nil if choice_array.blank?
        return nil if choice_array.any? { |c| c < 0 || c > max_option_idx }

        if proposal.respond_to?(:single_choice?) && proposal.single_choice?
          [choice_array.first]
        else
          choice_array.uniq
        end
      end
    end
  end
end
