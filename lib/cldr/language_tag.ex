defmodule Cldr.LanguageTag do
  alias Cldr.LanguageTag.Parser

  defstruct language: nil, script: nil, region: nil, variant: nil, locale: %{},
            transforms: %{}, extensions: %{}, private_use: []

  def parse(locale_string) do
    Parser.parse(locale_string)
  end

  def parse!(locale_string) do
    Parser.parse!(locale_string)
  end

  def parse_locale(%{language: language, script: script, region: region} = language_tag) do
    locale =
      [language, script, region]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("-")

    {:ok, locale, language_tag}
  end

  def parse_locale(locale_string) when is_binary(locale_string) do
    case parse(locale_string) do
      {:ok, language_tag} -> parse_locale(language_tag)
      {:error, reason} -> {:error, reason}
    end
  end

  def parse_locale!(locale_string) when is_binary(locale_string) do
    case parse_locale(locale_string) do
      {:ok, locale, _language_tag} -> locale
      {:error, {exception, reason}} -> raise exception, reason
    end
  end

end