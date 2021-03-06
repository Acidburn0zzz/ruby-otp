require 'digest'
require "openssl"
require 'yaml'

class OTP
    attr_accessor :hex, :sentence, :algo
    @@words = YAML.load_file('lib/dict.yaml')
    @@algo_map = {'md4' => OpenSSL::Digest::MD4,
                  'md5' => Digest::MD5,
                  'sha1' => Digest::SHA1,
                  'sha256' => Digest::SHA2.new(bitlen = 256),
                  'sha384' => Digest::SHA2.new(bitlen = 384),
                  'sha512' => Digest::SHA2.new(bitlen = 512) }

    def initialize(algo_str = 'md5')
        @hash = ""
        @hex = ""
        @sentence = ""
        @algo = @@algo_map[algo_str]
    end

    # generate a pseudo-random seed like "gh1234" or "zf4326"
    def self.generate_seed
      ( (0..1).collect { (rand(26) + 97).chr } +
        (0..3).collect { (rand(10) + 48).chr }).join("")
    end

    # create an OTP instance.
    # +passphrase+ length must be >= 10 and <= 63.
    # +passphrase+ must only contains pure ascii characters (7 bits).
    # +seed+ should only contains alpha-numeric characters.
    # +seed+ must not contain spaces
    # +algo_str+ can be "md4", "md5" (default), "sha1", "sha256", "sha384",
    # "sha512".
    def calculate(seq_num, seed, passphrase)
        raise ArgumentError, 'passphrase must be from 10 to 63 characters long' unless (10..63).include?(passphrase.size)

        passphrase.each_byte do |b|
            raise ArgumentError, 'passphrase contains non-ASCII characters' if b > 127
        end

        if seed =~ /\s/
             raise ArgumentError, "seed must not contain spaces"
        end

        if seed.match(/[\W|_]/)
            raise ArgumentError, "seed contains non alpha-numeric characters"
        end

        if seed.length > 16
            raise ArgumentError, "seed must between 1 and 16 characters in length"
        end

        @hash = seed.downcase + passphrase

        (seq_num+1).times do
            regs = @algo.digest(@hash).unpack("V*")
            times_to_fold = regs.size - 2
            0.upto(times_to_fold - 1) do |i|
                regs[i%2] ^= regs[i+2]
            end
            @hash = [regs[0], regs[1]].pack("V2")
        end
        @hex = to_hex
        @sentence = to_s
    end

    # return integer for this OTP
    def to_i
        @hash.unpack('H*')[0].to_i(16)
    end

    # return words sentence for this OTP
    def to_s
        parity = 0
        wi = tmplong = to_i
        sentence = ""

        32.times do |i|
            parity += tmplong & 3
            tmplong >>= 2
        end

        4.downto(0) do |i|
            sentence << @@words[ ((wi >> (i * 11 + 9)) & 0x7ff)] + " "
        end

        sentence << @@words[ ((wi << 2) & 0x7fc) | (parity & 3) ]
        sentence
    end

    # translate sentence to hex for comparison
    def sentence_to_hex(sentence)
        big_bin = ""
        word_in_bin = ""
        sentence = sentence.split(" ")
        sentence.each do |word|
            word_in_bin = @@words.index(word).to_s(2)
            if word_in_bin.size < 11
                temp = word_in_bin.reverse
                size = temp.size
                (11 - size).times do
                    temp << "0"
                end
                word_in_bin = temp.reverse
            end
        big_bin << word_in_bin
        end
        big_bin[0..63].to_i(2).to_s(16).upcase
    end

    # return response in hex form
    def to_hex
        to_i.to_s(16).upcase
    end

    # TODO
    def verified?(known, candidate)
        if candidate.match(/\d/)
            # return true if Hash(candidate) == known
            number = candidate.to_i(16)
            @hash = ["#{number}"].pack("H*")
            run_hashing_algo(@hash).to_hex
        else
            # return true if Hash(sentence_to_hex(candidate)) == known
        end
        return false
    end
end
