# based on http://cpan.uwinnipeg.ca/htdocs/Text-Glob/Text/Glob.pm.html#glob_to_regex_string from https://github.com/alexch/rerun/blob/master/lib/rerun/glob.rb

module Condenser::Rails
  module Utils
    NO_LEADING_DOT = '(?=[^\.])'   # todo
    START_OF_FILENAME = '(\A|\/)'  # beginning of string or a slash
    END_OF_STRING = '\z'

    def self.smoosh chars
      out = []
      until chars.empty?
        char = chars.shift
        if char == "*" and chars.first == "*"
          chars.shift
          chars.shift if chars.first == "/"
          out.push("**")
        else
          out.push(char)
        end
      end
      out
    end

    def self.glob_to_regex(glob_string)
      chars = smoosh(glob_string.split(''))

      curlies = 0
      escaping = false
      string = chars.map do |char|
        if escaping
          escaping = false
          char
        else
          case char
            when '**'
              "([^/]+/)*"
            when '*'
              ".*"
            when "?"
              "."
            when "."
              "\\."

            when "{"
              curlies += 1
              "("
            when "}"
              if curlies > 0
                curlies -= 1
                ")"
              else
                char
              end
            when ","
              if curlies > 0
                "|"
              else
                char
              end
            when "\\"
              escaping = true
              "\\"

            else
              char

          end
        end
      end.join
      
      Regexp.new(START_OF_FILENAME + string + END_OF_STRING)
    end
    
  end
end