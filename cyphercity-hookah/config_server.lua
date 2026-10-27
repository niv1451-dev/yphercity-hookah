--[[
    הגדרות צד-שרת בלבד. הקובץ הזה לא נשלח לשחקנים.
    גם כאן לא כותבים סיסמאות או כתובות Webhook ישירות — משתמשים ב-convar
    בקובץ server.cfg (ראו README).
]]

ServerConfig = {}

ServerConfig.Logging = {
    console = true,             -- הדפסת לוגים לקונסולה של השרת
    debug = false,              -- הדפסת לוגים ברמת debug
    memorySize = 250,           -- כמה רשומות אחרונות לשמור בזיכרון (מוצגות בפאנל הניהול)

    -- שליחת לוגים ל-Discord. כתובת ה-Webhook נקראת מ-convar בשרת בלבד:
    --     set cyphercity_hookah_webhook "https://discord.com/api/webhooks/...."
    -- (חשוב: set ולא setr — setr חושף את הערך לשחקנים)
    discord = {
        enabled = false,
        convar = 'cyphercity_hookah_webhook',
        username = 'CypherCity Hookah',
        -- אילו קטגוריות לשלוח: order, payment, table, hookah, staff, security, system
        categories = { payment = true, staff = true, security = true },
    },
}

-- שמירת סיכומי מכירות לקובץ JSON בתוך תיקיית המשאב (ללא מסד נתונים).
-- כבוי = הנתונים נשמרים בזיכרון בלבד ומתאפסים בהפעלה מחדש.
ServerConfig.Persistence = {
    enabled = true,
    file = 'data/sales.json',
    saveInterval = 60,          -- שמירה לכל היותר פעם בדקה (רק אם היה שינוי)
    keepDays = 30,
}

-- הרשאות ניהול לפי מזהה שחקן (חלופה ל-Job, שימושי במצב Standalone).
-- המזהה הוא license:..., discord:..., fivem:... (רואים אותו ב-txAdmin → Players).
-- דוגמה:
--   ['license:1234567890abcdef1234567890abcdef12345678'] = 'manager',
ServerConfig.StaffIdentifiers = {
}

-- הרשאת ACE לכלי האבחון ולפקודת הקואורדינטות:
--     add_ace group.admin cyphercity.hookah.admin allow
ServerConfig.AdminAce = 'cyphercity.hookah.admin'
