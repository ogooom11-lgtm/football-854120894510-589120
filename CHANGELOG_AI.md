# تحسينات مشروع "Bomban Futbol" - سجل التغييرات

## 🎯 الهدف
إضافة طور الذكاء الاصطناعي (لاعب ضد الكمبيوتر) مع مستويات صعوبة متعددة.

---

## 📁 الملفات المضافة

### 1. `lib/src/game/enums/ai_difficulty.dart` (جديد)
- تعداد `AiDifficulty` بثلاث مستويات: `easy`, `medium`, `hard`
- خصائص لكل مستوى:
  - `reactionFactor` - سرعة رد الفعل
  - `errorFactor` - نسبة الأخطاء
  - `aggressionFactor` - شراسة الهجوم والضغط
  - `visionRange` - مدى الرؤية التكتيكية
  - `anticipationFactor` - القدرة على توقع التمريرات والتسديدات

---

## 📝 الملفات المعدلة

### 2. `lib/src/game/models/team_setup.dart`
- إضافة `blueAiControlled`, `redAiControlled`, `aiDifficulty` إلى `MatchSetup`

### 3. `lib/src/game/logic/match_engine.dart`
- استيراد `ai_difficulty.dart`
- إضافة حقول `blueAiControlled`, `redAiControlled`, `aiDifficulty`
- تمرير مستوى الصعوبة إلى `PlayerAi` و `GoalkeeperAi`
- تعطيل الإدخال اليدوي للفرق التي يتحكم بها الذكاء الاصطناعي في `moveControlledTeam` و `manualKick`
- إضافة نظام التحكم الذاتي للذكاء الاصطناعي:
  - `_tickAiAutoControl()` - المنسق الرئيسي
  - `_tickAiTeam()` - تحكم بفريق واحد
  - `_aiMovementTarget()` - تحديد موقع الحركة التكتيكي
  - `_tickAiKickDecision()` - قرارات التمرير والتسديد
  - `_tickAiPenalty()` - قرارات ركلات الجزاء
  - `_movePlayerDirect()` - تحريك مباشر للاعب (يتجاوز فحص AI)

### 4. `lib/src/game/logic/player_ai.dart`
- إضافة معامل `difficulty` إلى الصانع (constructor)
- دمج مستوى الصعوبة في:
  - عتبة قرار التسديد
  - سرعة الهجمة المرتدة
  - قرار العرضية
  - اختيار التمريرة الآمنة

### 5. `lib/src/game/logic/goalkeeper_ai.dart`
- إضافة معامل `difficulty` إلى الصانع
- دمج مستوى الصعوبة في:
  - مدى اكتشاف التسديدات
  - فرصة الإمساك بالكرة
  - سلوك الخروج للمواجهة

### 6. `lib/src/screens/game_screen.dart`
- تعطيل مفاتيح التحكم للفرق التي يتحكم بها الذكاء الاصطناعي
- إضافة دوال `_isBlueActionKey` و `_isRedActionKey` لتصنيف المفاتيح
- عرض حالة الذكاء الاصطناعي في شاشة اللعبة

### 7. `lib/src/screens/setup_screen.dart`
- إضافة لوحة تحكم الذكاء الاصطناعي:
  - تفعيل/تعطيل AI لكل فريق
  - اختيار مستوى الصعوبة
- حفظ الإعدادات تلقائياً

### 8. `lib/src/storage/roster_storage.dart`
- إضافة `blueAiControlled`, `redAiControlled`, `aiDifficulty` إلى `SavedGameData`
- حفظ وتحميل إعدادات الذكاء الاصطناعي من/إلى JSON

---

## 🎮 كيفية الاستخدام

1. **تشغيل التطبيق** - ادخل إلى شاشة الإعداد
2. **تفعيل AI** - في لوحة "Yapay Zeka (AI) Ayarlari":
   - فعل AI للفريق الأزرق أو الأحمر أو كليهما
   - اختر مستوى الصعوبة (Kolay/Orta/Zor)
3. **ابدأ المباراة** - العب ضد الذكاء الاصطناعي أو شاهد مباراة AI vs AI
4. **التحكم اليدوي** - إذا كان الفريق تحت التحكم اليدوي، استخدم:
   - **الفريق الأزرق**: الأسهم + Numpad 1/2/3
   - **الفريق الأحمر**: WASD + 1/2/3

---

## ⚙️ مستويات الصعوبة

| المستوى | الوصف |
|---------|-------|
| **Kolay (سهل)** | أخطاء أكثر، ردود أبطأ، هجوم أقل شراسة |
| **Orta (متوسط)** | متوازن - المستوى الافتراضي |
| **Zor (صعب)** | أخطاء أقل، ردود أسرع، قرارات تكتيكية أفضل |
