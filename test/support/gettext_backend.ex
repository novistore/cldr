defmodule TestGettext.Gettext do
  @moduledoc """
  Implements a Gettext-compatible module but using Cldr locales.  Its for
  testing only.
  """
  use Gettext,
    otp_app: Cldr.Config.app_name(),
    priv: "priv/gettext_test",
    plural_forms: TestBackend.Gettext.Plural

end

