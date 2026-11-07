import Base
import ../src/cli/token.bend as T

# Spec for src/cli/token.bend: vcluster token create --expires, parsed by
# Go's time.ParseDuration. Expected values come from running Go 1.26 on
# each input (whole seconds; negatives are a vk8s refusal).

law token.duration.case1:
  {T.Tok.duration("1h") == T.Dur{True{}, 3600, ""} : T.Dur}

law token.duration.case2:
  {T.Tok.duration("30m") == T.Dur{True{}, 1800, ""} : T.Dur}

law token.duration.case3:
  {T.Tok.duration("90s") == T.Dur{True{}, 90, ""} : T.Dur}

law token.duration.case4:
  {T.Tok.duration("1h30m") == T.Dur{True{}, 5400, ""} : T.Dur}

law token.duration.case5:
  {T.Tok.duration("24h") == T.Dur{True{}, 86400, ""} : T.Dur}

law token.duration.case6:
  {T.Tok.duration("1d") == T.Dur{False{}, 0, "time: unknown unit \"d\" in duration \"1d\""} : T.Dur}

law token.duration.case7:
  {T.Tok.duration("1w") == T.Dur{False{}, 0, "time: unknown unit \"w\" in duration \"1w\""} : T.Dur}

law token.duration.case8:
  {T.Tok.duration("1") == T.Dur{False{}, 0, "time: missing unit in duration \"1\""} : T.Dur}

law token.duration.case9:
  {T.Tok.duration("x") == T.Dur{False{}, 0, "time: invalid duration \"x\""} : T.Dur}

law token.duration.case10:
  {T.Tok.duration("") == T.Dur{False{}, 0, "time: invalid duration \"\""} : T.Dur}

law token.duration.case11:
  {T.Tok.duration("0") == T.Dur{True{}, 0, ""} : T.Dur}

law token.duration.case12:
  {T.Tok.duration("2h45m10s") == T.Dur{True{}, 9910, ""} : T.Dur}

law token.duration.case13:
  {T.Tok.duration("1.5h") == T.Dur{True{}, 5400, ""} : T.Dur}

law token.duration.case15:
  {T.Tok.duration("1H") == T.Dur{False{}, 0, "time: unknown unit \"H\" in duration \"1H\""} : T.Dur}

# vk8s refuses a negative duration.
law token.duration.negative:
  {T.Tok.duration("-1h") == T.Dur{False{}, 0, "vk8s: --expires \"-1h\" is negative"} : T.Dur}
