# frozen_string_literal: true

require 'ipaddr'
require 'uri'

module DiscourseSiwe
  # Shared, strict URL validation for URLs that originate from external
  # contracts, subgraphs, or ENS metadata. Used by identity resolution and
  # avatar download enqueuing to reduce SSRF / local-network surface.
  module UrlValidator
    module_function

    ALLOWED_SCHEMES = %w[http https ipfs].freeze

    PRIVATE_CIDRS = %w[
      127.0.0.0/8
      10.0.0.0/8
      172.16.0.0/12
      192.168.0.0/16
      169.254.0.0/16
      fc00::/7
      fe80::/10
      ::1/128
    ].map { |c| IPAddr.new(c) }.freeze

    # Returns a normalized HTTPS URL, or nil if the URL is unsafe/unsupported.
    # ipfs://<cid> is rewritten to the configured HTTPS gateway.
    def normalize(url, ipfs_gateway: 'https://ipfs.io/ipfs/')
      url = url.to_s.strip
      return nil if url.empty?

      normalized = url.start_with?('ipfs://') ? "#{ipfs_gateway}#{url.sub('ipfs://', '')}" : url
      safe?(normalized) ? normalized : nil
    end

    # Returns true for http(s) public destinations and ipfs:// URIs with a path.
    def safe?(url)
      uri = URI.parse(url.to_s)
      return false unless ALLOWED_SCHEMES.include?(uri.scheme)

      if uri.scheme == 'ipfs'
        path = uri.path.to_s.strip
        return !path.empty? && path.length > 1
      end

      return false if uri.host.to_s.strip.empty?
      return false if uri.host.match?(/\A(localhost|localhost\.localdomain)\z/i)

      begin
        ip = IPAddr.new(uri.host)
        return false if PRIVATE_CIDRS.any? { |c| c.include?(ip) }
      rescue IPAddr::InvalidAddressError
        # Not an IP address; treat as a public domain name.
      end

      true
    rescue URI::Error
      false
    end
  end
end
