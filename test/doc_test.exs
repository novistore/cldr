defmodule Doc.Test do
  use ExUnit.Case
  doctest Cldr
  doctest Cldr.Config
  doctest Cldr.Locale

  doctest Cldr.LanguageTag
  doctest Cldr.LanguageTag.Parser
  doctest Cldr.AcceptLanguage
  doctest Cldr.Substitution

  doctest TestBackend.Cldr
  doctest TestBackend.Cldr.Number.Ordinal
  doctest TestBackend.Cldr.Number.Cardinal
  doctest TestBackend.Cldr.Gettext.Plural
  doctest TestBackend.Cldr.Number.PluralRule.Range
end
