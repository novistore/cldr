defmodule Cldr.Number do
  @moduledoc """
  ## Cldr formatting for numbers.
  
  Provides the public API for the formatting of numbers based upon
  CLDR's decimal formats specification documentated [Unicode TR35]
  (http://unicode.org/reports/tr35/tr35-numbers.html#Number_Formats)
  
  ### Non-Scientific Notation Formatting
  
  The following description applies to formats that do not use scientific
  notation or significant digits:

  * If the number of actual integer digits exceeds the maximum integer digits,
  then only the least significant digits are shown. For example, 1997 is
  formatted as "97" if the maximum integer digits is set to 2.

  * If the number of actual integer digits is less than the minimum integer
  digits, then leading zeros are added. For example, 1997 is formatted as
  "01997" if the minimum integer digits is set to 5.

  * If the number of actual fraction digits exceeds the maximum fraction
  digits, then half-even rounding it performed to the maximum fraction digits.
  For example, 0.125 is formatted as "0.12" if the maximum fraction digits is
  2. This behavior can be changed by specifying a rounding increment and a
  rounding mode.

  * If the number of actual fraction digits is less than the minimum fraction
  digits, then trailing zeros are added. For example, 0.125 is formatted as
  "0.1250" if the minimum fraction digits is set to 4.

  * Trailing fractional zeros are not displayed if they occur j positions
  after the decimal, where j is less than the maximum fraction digits. For
  example, 0.10004 is formatted as "0.1" if the maximum fraction digits is 
  four or less.
 
  ### Scientific Notation Formatting
  
  Numbers in scientific notation are expressed as the product of a mantissa and
  a power of ten, for example, 1234 can be expressed as 1.234 x 103. The
  mantissa is typically in the half-open interval [1.0, 10.0) or sometimes
  [0.0, 1.0), but it need not be. In a pattern, the exponent character
  immediately followed by one or more digit characters indicates scientific
  notation. Example: "0.###E0" formats the number 1234 as "1.234E3".
  
  * The number of digit characters after the exponent character gives the
  minimum exponent digit count. There is no maximum. Negative exponents are
  formatted using the localized minus sign, not the prefix and suffix from the
  pattern. This allows patterns such as "0.###E0 m/s". To prefix positive
  exponents with a localized plus sign, specify '+' between the exponent and
  the digits: "0.###E+0" will produce formats "1E+1", "1E+0", "1E-1", and so
  on. (In localized patterns, use the localized plus sign rather than '+'.)

  * The minimum number of integer digits is achieved by adjusting the
  exponent. Example: 0.00123 formatted with "00.###E0" yields "12.3E-4". This
  only happens if there is no maximum number of integer digits. If there is a
  maximum, then the minimum number of integer digits is fixed at one.

  * The maximum number of integer digits, if present, specifies the exponent
  grouping. The most common use of this is to generate engineering notation,
  in which the exponent is a multiple of three, for example, "##0.###E0". The
  number 12345 is formatted using "##0.####E0" as "12.345E3".

  * When using scientific notation, the formatter controls the digit counts
  using significant digits logic. The maximum number of significant digits
  limits the total number of integer and fraction digits that will be shown in
  the mantissa; it does not affect parsing. For example, 12345 formatted with
  "##0.##E0" is "12.3E3". Exponential patterns may not contain grouping
  separators.

  ### Significant Digits

  There are two ways of controlling how many digits are shows: (a)
  significant digits counts, or (b) integer and fraction digit counts. Integer
  and fraction digit counts are described above. When a formatter is using
  significant digits counts, it uses however many integer and fraction digits
  are required to display the specified number of significant digits. It may
  ignore min/max integer/fraction digits, or it may use them to the extent
  possible.
  """
  import Cldr.Macros
  import Cldr.Number.String
  import Cldr.Number.Format, only: [format_from: 2]
  import Cldr.Number.Transliterate, only: [transliterate: 3]
  import Cldr.Number.Symbol, only: [number_symbols_for: 2, 
                                    minimum_grouping_digits_for: 1]
  
  alias Cldr.Number.Format.Compiler
  alias Cldr.Currency

  @type format_type :: 
    :standard | 
    :short | 
    :long | 
    :percent |
    :accounting |
    :scientific

  @default_options [
    as:            :standard,
    currency:      nil,
    cash:          false,
    rounding_mode: :half_even,
    number_system: :default, 
    locale:        Cldr.default_locale()
  ]
  
  @spec to_string(number, [Keyword.t]) :: String.t
  def to_string(number, options \\ @default_options) do
    options = options
    |> normalize_options(@default_options)
    |> detect_negative_number(number)
    
    if options[:format] do
      options = options |> Keyword.delete(:as)
      format = options[:format]
      to_string(number, format, options)
    else
      options = options |> Keyword.delete(:format)
      format = options[:locale] 
        |> format_from(options[:number_system]) 
        |> Map.get(options[:as])
      to_string(number, format, options)
    end
  end
  
  # Compile the known decimal formats extracted from the 
  # current configuration of Cldr.  This avoids having to tokenize
  # parse and analyse the format on each invokation.  There
  # are around 74 Cldr defined decimal formats so this isn't
  # to burdensome on the compiler of the BEAM.
  Enum.each Cldr.Number.Format.decimal_format_list(), fn format ->
    case Compiler.decode(format) do
    {:ok, meta} ->
      defp to_string(number, unquote(format), options) do
        do_to_string(number, unquote(Macro.escape(meta)), options)
      end
    {:error, message} ->
      {:error, message}
    end
  end
  
  # For formats not precompiled we need to compile first
  # and then process
  defp to_string(number, format, options) do
    case Compiler.decode(format) do
    {:ok, meta} ->
      do_to_string(number, meta, options)
    {:error, message} ->
      {:error, message}
    end
  end
  
  # Now we have the number to be formatted, the meta data that 
  # defines the formatting and the options to be applied 
  # (which is related to localisation of the final format)
  defp do_to_string(number, meta, options) do
    meta = meta 
    |> adjust_fraction_for_currency(options[:currency], options[:cash])
    
    number
    |> to_decimal
    |> multiply_by_factor(meta[:multiplier])
    |> round_to_nearest(meta[:rounding], options[:rounding_mode])
    |> output_to_string(meta[:fractional_digits], options[:rounding_mode])
    |> adjust_leading_zeroes(:integer, meta[:integer_digits])
    |> adjust_trailing_zeroes(:fraction, meta[:fractional_digits])
    |> apply_grouping(meta[:grouping], options[:locale]) # 20 µs/op
    |> reassemble_number_string
    |> transliterate(options[:locale], options[:number_system]) # 80 µs/op
    |> apply_padding(meta[:padding_length], meta[:padding_char])
    |> assemble_format(number, meta[:format], options) # 10 µs/op
  end

  # When formatting a currency we need to adjust the number of fractional
  # digits to match the currency definition.  We also need to adjust the
  # rounding increment to match the currency definition.
  defp adjust_fraction_for_currency(meta, nil, _cash) do
    meta
  end
  
  defp adjust_fraction_for_currency(meta, currency, cash) when is_false(cash) do
    currency = Currency.for_code(currency)
    do_adjust_fraction(meta, currency.digits, currency.rounding)
  end
  
  defp adjust_fraction_for_currency(meta, currency, _cash) do
    currency = Currency.for_code(currency)
    do_adjust_fraction(meta, currency.cash_digits, currency.cash_rounding)
  end
  
  defp do_adjust_fraction(meta, digits, rounding) do
    rounding = Decimal.new(:math.pow(10, -digits) * rounding)
    %{meta | fractional_digits: %{max: digits, min: digits},
             rounding: rounding}
  end
  
  # Convert the number to a decimal since it preserves precision
  # better when we round.  Then use the absolute value since
  # the sign only determines which pattern we use (positive
  # or negative)
  defp to_decimal(number = %Decimal{}) do
    number 
    |> Decimal.abs()
  end
  
  defp to_decimal(number) do
    number
    |> Decimal.new
    |> Decimal.abs()
  end
  
  # If the format includes a % (percent) or permille then we
  # adjust the number by a factor.  All other formats the factor
  # is 1 and hence we avoid the multiplication.
  defp multiply_by_factor(number, %Decimal{coef: 1} = _factor) do
    number
  end
  
  defp multiply_by_factor(number, factor) do
    Decimal.mult(number, factor)
  end
  
  # A format can include a rounding specification which we apply
  # here execpt if there is no rounding specified.
  defp round_to_nearest(number, %Decimal{coef: 0}, _rounding_mode) do
    number
  end
  
  defp round_to_nearest(number, rounding, rounding_mode) do
    number
    |> Decimal.div(rounding)
    |> Decimal.round(0, rounding_mode)
    |> Decimal.mult(rounding)
  end
  
  # Output the number to a string - all the other transformations
  # are done on the string version split into its constituent
  # parts
  defp output_to_string(number, fraction_digits, rounding_mode) do
    string = number
    |> Decimal.round(fraction_digits[:max], rounding_mode)
    |> Decimal.to_string(:normal)
    
    Regex.named_captures(Compiler.number_match_regex(), string)
  end
  
  # Remove all the trailing zeroes from a fraction and add back what
  # is required for the format
  defp adjust_trailing_zeroes(number, :fraction, fraction_digits) do
    fraction = String.trim_trailing(number["fraction"], "0")
    %{number | "fraction" => pad_trailing_zeroes(fraction, fraction_digits[:min])}
  end
  
  defp adjust_trailing_zeroes(number, _fraction, _fraction_digits) do
    number
  end
 
  # Remove all the leading zeroes from an integer and add back what
  # is required for the format
  defp adjust_leading_zeroes(number, :integer, integer_digits) do
    integer = String.trim_leading(number["integer"], "0")
    %{number | "integer" => pad_leading_zeroes(integer, integer_digits[:min])}
  end

  defp adjust_leading_zeroes(number, _integer, _integer_digits) do
    number
  end
  
  # Insert the grouping placeholder in the right place in the number.
  # There may be one or two different groupings for the integer part
  # and one grouping for the fraction part.
  defp apply_grouping(%{"integer" => integer, "fraction" => fraction} = string, groups, locale) do
    integer = do_grouping(integer, groups[:integer], 
                String.length(integer), 
                minimum_group_size(groups[:integer], locale), 
                :reverse)
    
    fraction = do_grouping(fraction, groups[:fraction], 
                 String.length(fraction), 
                 minimum_group_size(groups[:fraction], locale))
    
    %{string | "integer" => integer, "fraction" => fraction}
  end
  
  defp minimum_group_size(%{first: group_size}, locale) do
    minimum_grouping_digits_for(locale) + group_size
  end
  
  # The actual grouping function.  Note there are two directions,
  # `:forward` and `:reverse`.  Thats because we group from the decimal
  # placeholder outwards and there may be a final group that is less than
  # the grouping size.  For the fraction part the dangling part is at the
  # end (:forward direction) whereas for the integer part the dangling
  # group is at the beginning (:reverse direction)
  defp do_grouping(string, groups, string_length, min_grouping, direction \\ :forward)
  
  # No grouping if the string length (number of digits) is less than the
  # minimum grouping size.
  defp do_grouping(string, _, string_length, min_grouping, _) when string_length < min_grouping do
    string
  end
  
  # The case when there is only one grouping. Always true for fraction part.
  @group_separator Compiler.placeholder(:group)
  defp do_grouping(string, %{first: first, rest: rest}, _, _, direction) when first == rest do
    string
    |> chunk_string(first, direction)
    |> Enum.join(@group_separator)
  end

  # The case when there are two different groupings. This applies only to
  # The integer part, it can never be true for the fraction part.
  defp do_grouping(string, %{first: first, rest: rest}, string_length, _, :reverse) do
    {rest_of_string, first_group} = String.split_at(string, string_length - first)
    other_groups = chunk_string(rest_of_string, rest, :reverse)
    Enum.join(other_groups ++ [first_group], Compiler.placeholder(:group))
  end

  # Put the parts of the number back together again
  defp reassemble_number_string(%{"fraction" => ""} = number) do
    number["integer"]
  end
  
  # When there is both an integer and fraction parts
  @decimal_separator Compiler.placeholder(:decimal)
  defp reassemble_number_string(number) do
    number["integer"] <>  @decimal_separator <> number["fraction"]
  end
   
  # Pad the number to the format length
  defp apply_padding(number, 0, _char) do
    number
  end
  
  defp apply_padding(number, length, char) do
    String.pad_leading(number, length, char)
  end
  
  # Now we can assemble the final format.  Based upon
  # whether the number is positive or negative (as indicated
  # by options[:sign]) we assemble the parts and transliterate
  # the currency sign, percent and permille characters.
  @lint {~r/Refactor/, false}
  defp assemble_format(number_string, number, format, options) do
    format = format[options[:pattern]]
    format_length = length(format)
    do_assemble_format(number_string, number, format, options, format_length)
  end
  
  # If the format length is 1 (one) then it can only be the number format
  # and therefore we don't have to do the reduction.
  def do_assemble_format(number_string, _number, _format, _options, 1) do
    number_string
  end
  
  def do_assemble_format(number_string, number, format, options, _length) do
    system = options[:number_system]
    locale = options[:locale]
    symbols = number_symbols_for(locale, system)
  
    Enum.reduce format, "", fn (token, string) ->
      string <> case token do
        {:format, _format}  -> number_string
        {:pad, _}           -> ""
        {:plus, _}          -> symbols.plus_sign
        {:minus, _}         -> symbols.minus_sign
        {:currency, type}   -> 
          currency_symbol(options[:currency], number, type, locale)
        {:percent, _}       -> symbols.percent_sign
        {:permille, _}      -> symbols.permille
        {:literal, literal} -> literal
        {:quote, char}      -> char
        {:quote_char, char} -> char
      end
    end
  end
  
  # Extract the appropriate currency symbol based upon how many currency
  # placeholders are in the format as follows:
  #   ¤      Standard currency symbol
  #   ¤¤     ISO currency symbol (constant)
  #   ¤¤¤    Appropriate currency display name for the currency, based on the
  #          plural rules in effect for the locale
  #   ¤¤¤¤¤  Narrow currency symbol.
  defp currency_symbol(%Cldr.Currency{} = currency, _number, 1, _locale) do
    currency.symbol
  end
  
  defp currency_symbol(%Cldr.Currency{} = currency, _number, 2, _locale) do
    currency.code
  end
 
  defp currency_symbol(%Cldr.Currency{} = currency, number, 3, locale) do
    selector = Cldr.Number.Cardinal.plural_rule(number, locale)
    currency.count[selector] || currency.count[:other]
  end
 
  defp currency_symbol(%Cldr.Currency{} = currency, _number, 5, _locale) do
    currency.narrow_symbol || currency.symbol
  end
  
  defp currency_symbol(nil, _number, _type, _locale) do
    raise ArgumentError, message: """
      Cannot use a format with a currency place holder
      unless `option[:currency] is set to a currency code.
    """
  end
  
  defp currency_symbol(currency, number, size, locale) do
    currency = Currency.for_code(currency, locale) 
    currency_symbol(currency, number, size, locale)
  end
  
  # Merge options and default options with supplied options always
  # the winner.
  defp normalize_options(options, defaults) do
    Keyword.merge defaults, options, fn _k, _v1, v2 -> v2 end
  end
  
  defp detect_negative_number(options, number)
      when (is_float(number) or is_integer(number)) and number < 0 do
    Keyword.put(options, :pattern, :negative)
  end
  
  defp detect_negative_number(options, %Decimal{sign: sign}) when sign < 0 do
    Keyword.put(options, :pattern, :negative)
  end
  
  defp detect_negative_number(options, _number) do
    Keyword.put(options, :pattern, :positive)
  end
end 