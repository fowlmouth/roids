type
  TEither* [A,B] = object
    case isFirst*: bool
    of true: first*: A
    else:   second*: B


proc Left* [B] (some: A): TEither[A,B] =
  result.isFirst = true
  result.first = some
proc Right*[A] (some: B): TEither[A,B] =
  result.isFirst = false
  result.second = some

