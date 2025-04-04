local _, fPB = ...

if GetLocale() ~= "zhCN" then return end

--You can help with translation at https://wow.curseforge.com/projects/flyplatebuffs/localization

local L = fPB.L

L[" already in the list."] = "已在列表中的"
L[" ID changed "] = "ID已更改"
L[" Incorrect ID"] = "错误ID"
L[" It is ID of completely different spell "] = "完全不同法术的ID"
L[". You can add it by using top editbox."] = "可通过顶部编辑框添加"
L["Add new spell to list"] = "添加新法术到列表"
L["Addon will no longer control this CVar on login"] = "登录时插件不再控制此CVar参数"
L["All"] = "全部"
L["Allies"] = "友善"
L["Also will show duration if OmniCC installed, regardless of the previous option"] = "如安裝了OmniCC, 仍然会显示持续时间, 并忽略前面的设定"
L["Always"] = "总是"
L["Always show icons with full opacity and size"] = "始终显示完整的透明度和大小的图标"
L["Base height"] = "高度"
L["Base width"] = "宽度"
L["Blink spell if below x% time left (only if it's below 60 seconds)"] = "剩余时间低于X%闪烁(只对60秒以下的光环生效)"
L["Blink when close to expiring"] = "快消失时闪烁"
L["Border"] = "边框"
L["Border Style"] = "边框样式"
L["Buff frame will be anchored to this point of the nameplate"] = "Buff框体将固定在姓名板的这个位置"
L["Buff frame's Anchor point"] = "Buff框体锚点位置"
L["Buffs"] = "增益buff"
L[ [=[Changes CVar "nameplateMaxDistance".
Legion default = 60. Old default = 40.]=] ] = [=[更改CVars参数 "nameplateMaxDistance".
军团再临初始值为60，以前默认设置为40.]=]
L["Check spell ID"] = "检查法术ID"
L["Color debuff border by type"] = "根据光环类型为减益边框着色"
L["Crop texture"] = "裁减纹理"
L["Crop texture instead of stretching. You can see the difference on rectangular icons"] = "裁剪纹理而不是拉伸.你可以在矩形图标上看到不同"
L["Curse"] = "诅咒"
L["CVars"] = "CVar参数"
L["CVars & Other"] = "CVars和其他参数"
L["Debuff > Buff"] = "Debuff优先于Buff"
L["Disable sorting"] = "禁用排序"
L["Disease"] = "疾病"
L["Display conditions"] = "显示条件"
L["Display options"] = "显示设定"
L["Do not show effects without duration."] = "不显示无持续时间的光环"
L["Duration font size"] = "持续时间文字大小"
L["Duration on icon"] = "在图标上显示持续时间"
L["Duration under icon"] = "在图标下方显示持续时间"
L["Enemies"] = "敌对"
L[ [=[Enter spell ID or name (case sensitive)
and press OK]=] ] = [=[输入法术ID或名称(注意大小写)
然后按OK]=]
L["Excess buffs will not be displayed"] = "超过数量的光环会被隐藏"
L["Fix nameplates without names"] = "修正姓名版不显示姓名bug"
L["Font"] = "字体"
L["Hide permanent effects"] = "隐藏永久显示的光环"
L["Horizontal offset of buff frame"] = "buff框体水平偏移"
L["Horizontal spacing between icons"] = "图标间的水平间隔"
L["Icon scale"] = "图标比例"
L["Icon scale (Importance)"] = "图标比例(重要的)"
L["Icons per row"] = "每行图标数量"
L["Icons Size"] = "图标大小"
L[ [=[Icons will not change on nontargeted nameplates.

|cFFFF0000REALLY NOT RECOMMEND|r
When icons overlay there will be mess of textures, digits etc.]=] ] = "非当前目标的光环不会改变透明度/大小"
L["If more icons they will be moved to a new row"] = "超过数量的图标会放在下一行"
L["If not checked - physical used for all debuff types"] = "如果不选择=所有debuff用物理效果的边框"
L["Incorrect ID or name"] = "不正确的ID或名称"
L["Interval X"] = "水平间隔"
L["Interval Y"] = "垂直间隔"
L["It will be attached to the nameplate at this point"] = "将在这一点添加到姓名板上"
L["Larger self spells"] = "增大自己的光环"
L["Magic"] = "魔法"
L["Max rows"] = "最大行数"
L["Mine + SpellList"] = "我的 + 法术清单"
L["My spell"] = "我的法术"
L["Nameplate visible distance"] = "姓名版可见距离"
L["Nameplate's Anchor point"] = "姓名板锚点"
L["Neutrals"] = "中立"
L["Never"] = "永不"
L["No spell ID"] = "无法术ID"
L["None"] = "无"
L["NPCs"] = "NPC的"
L["Offset X"] = "水平偏移"
L["Offset Y"] = "垂直偏移"
L["On ally only"] = "只是友善"
L["On enemy only"] = "只是敌对"
L["Only mine"] = "只是我"
L["Only SpellList"] = "只是法术列表"
L["Pets"] = "宠物"
L["Physical"] = "物理"
L["Player in combat"] = "在战斗中的玩家"
L["Players"] = "玩家"
L["Poison"] = "中毒"
L["Position Settings"] = "位置设定"
L["Priority"] = "优先"
L["Profiles"] = "设定文件"
L["ReloadUI"] = "重新载入UI"
L["Remaining duration"] = "剩余时间"
L["Remove spell"] = "移除法术"
L["Reset to default"] = "重置为默认"
L["Reverse"] = "反向"
L["Save CVars"] = "保存CVars参数"
L["Sets CVars \"nameplateOtherTopInset\" and \"nameplateOtherBottomInset\" to -1"] = "将CVars 参数\\\"nameplateOtherTopInset\\\"和\\\"nameplateOtherBottomInset\\\"设定为-1"
L["Show"] = "显示"
L["Show buffs"] = "显示buff"
L["Show 'clock' animation"] = "显示'时钟'动画"
L["Show debuffs"] = "显示debuff"
L["Show on allies"] = "友方显示"
L["Show on enemies"] = "敌方显示"
L["Show on neutral characters"] = "中立方显示"
L["Show on NPCs"] = "显示在NPC上"
L["Show on pets"] = "显示在宠物"
L["Show on players"] = "显示在玩家"
L["Show only if player is in combat"] = "只当玩家在战斗中显示"
L["Show only if unit is in combat"] = "只当单位在战斗中显示"
L["Show remaining duration under icon"] = "在图标下面显示持续时间"
L["Show self spells x% bigger."] = "自己的图标增大x%"
L["Show spell ID in tooltips"] = "在鼠标处显示法术ID"
L["Some nameplate related Console Variables"] = "一些姓名版相关参数"
L["Sorting"] = "排序"
L["Specific spells"] = "指定法术"
L["Spell ID"] = "法术ID"
L["Spell with this ID is already in the list. Its name is "] = "这个法术ID已存在与列表中，名字是"
L["Square"] = "方形"
L["Stack font size"] = "堆叠数字体大小"
L["Stacks & Duration"] = "堆叠數和持续时间"
L["Stops nameplates from clamping to the screen"] = "避免姓名版飞出屏幕"
L["Style settings"] = "样式设定"
L["Support standart blizzard or OmniCC"] = "支持暴雪设定或OmniCC"
L["Unit in combat"] = "在战斗中的单位"
L[ [=[Usefull for configuring spell list.
Requires ReloadUI to turn off.]=] ] = "设定法术清单请后请关闭并重载UI"
L["Vertical offset of buff frame"] = "光环框架的垂直偏移"
L["Vertical spacing between icons"] = "图标间的水平偏移"
L["Start blinking when this percentage of duration remains"] = "当剩余时间百分比低于此值时开始闪烁"
L["Buffs and debuffs will start blinking when their remaining time falls below this percentage of their total duration."] = "当增益和减益效果的剩余时间低于其总持续时间的此百分比时，它们将开始闪烁。"
L["Background transparency"] = "背景透明度"
L["Adjust the transparency of the duration text background"] = "调整持续时间文本背景的透明度"
L["When enabled, Masque will override all border settings including colors and style."] = "启用后，Masque将覆盖所有边框设置，包括颜色和样式。"
L["Masque support enabled"] = "Masque支持已启用"
L["Masque support disabled"] = "Masque支持已禁用"
L["Border settings are now controlled by Masque"] = "边框设置现在由Masque控制"
L["Border settings restored to addon defaults"] = "边框设置已恢复为插件默认值"
L["Also in Performance tab"] = "也在性能选项卡中"
L["This setting is also available in the Performance tab."] = "此设置也可在性能选项卡中找到。"

