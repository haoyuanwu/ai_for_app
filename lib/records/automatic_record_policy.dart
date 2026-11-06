/// Automatic recording applies to concrete facts, never uncertain statements,
/// questions, quoted material, or an instruction to avoid saving.
class AutomaticRecordPolicy {
  static bool allows(String text) => !RegExp(
    r'好像|似乎|估计|听说|或许|或者|还是|不记|别保存|不保存|支付失败|待支付|未支付|交易关闭|如果|假如|假设|可能|大概|不确定|也许|预算|计划花|他说|她说|比如|例如|不要|不用|不必|取消|别记|先别|只记|仅记|除了|是否|要不要|能否|[？?]|[“”「」]|无法辨认|无法确认|未能确认|待确认|待核实',
  ).hasMatch(text);
}
