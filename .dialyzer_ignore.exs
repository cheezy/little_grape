# Dialyzer warnings intentionally ignored.
#
# Each entry is a {relative_file, warning_type} tuple. Keep this list minimal
# and documented — every entry must be a known upstream false positive, not a
# silenced real defect.
#
# All current entries are `:call_without_opaque` warnings caused by opaque
# types defined in dependencies crossing module boundaries — none are bugs in
# this project's code:
#
#   * matches.ex / swipes.ex — `Ecto.Multi` builds an opaque struct that
#     Dialyzer flags when piped through `Multi.insert/3` etc.
#   * gettext.ex — the `use Gettext.Backend` macro expands to a call passing
#     `Expo.PluralForms` (an opaque struct) into `Gettext.Plural.plural/2`.
[
  {"lib/little_grape/matches.ex", :call_without_opaque},
  {"lib/little_grape/swipes.ex", :call_without_opaque},
  {"lib/little_grape_web/gettext.ex", :call_without_opaque}
]
