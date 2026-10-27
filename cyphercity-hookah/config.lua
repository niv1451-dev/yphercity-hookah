--[[
    ╔══════════════════════════════════════════════════════════════════╗
    ║            המקום של השייח — טרקלין נרגילות — קובץ הגדרות          ║
    ╚══════════════════════════════════════════════════════════════════╝

    כל ההגדרות של העסק נמצאות כאן: מיקום, דמויות (NPC), שולחנות, תפריט,
    מחירים, הרשאות ואבטחה. אחרי כל שינוי יש להפעיל מחדש את המשאב:
        restart cyphercity-hookah      (בקונסולה של txAdmin)

    חשוב: הקובץ הזה נטען גם אצל השחקנים (shared). אין לשים כאן סיסמאות,
    מפתחות או כתובות Webhook. הגדרות רגישות נמצאות ב-config_server.lua
    ובמשתני convar של השרת.

    קואורדינטות: vec3(x, y, z) למיקום, vec4(x, y, z, heading) למיקום + כיוון.
    כדי לקבל קואורדינטות מדויקות במשחק: עמדו במקום והקלידו /hookahcoords
    (זמין כש-Config.Debug = true או למנהלי שרת עם הרשאת ACE מתאימה).

    המיקום שמוגדר כברירת מחדל הוא מיקום הדגמה בכיכר Legion Square עם רהיטים
    שנוצרים אוטומטית. בשרת אמיתי יש להחליף אותו במיקום ה-MLO של העסק.
]]

Config = {}

-- ═══════════════════════════════════════════════════════════════════
-- כללי
-- ═══════════════════════════════════════════════════════════════════

Config.Debug = false            -- true = ציור אזורים, הדפסות דיבאג ופקודת /hookahcoords לכולם
Config.Locale = 'he'            -- 'he' (עברית) או 'en' (English)

Config.Currency = {
    symbol = '₪',               -- סימן המטבע, לדוגמה '₪' או '$'
    position = 'after',         -- 'after' = 100 ₪ , 'before' = $100
    space = true,               -- רווח בין המספר לסימן (100 ₪ במקום 100₪)
}

-- ═══════════════════════════════════════════════════════════════════
-- אינטגרציות (Bridge)
-- ═══════════════════════════════════════════════════════════════════
-- 'auto' = זיהוי אוטומטי לפי המשאבים שפועלים בשרת.
-- אם הזיהוי האוטומטי נכשל, הקונסולה תציג הודעה מפורטת עם הוראות.
-- להפעלת כלי האבחון: הקלידו בקונסולה של השרת  hookahdiag

Config.Framework = 'auto'       -- 'auto' | 'esx' | 'qbcore' | 'qbox' | 'standalone'
Config.Inventory = 'none'       -- 'none' (מצב קטלוג בלבד, ללא פריטים) | 'auto' | 'ox_inventory' | 'qb-inventory' | 'esx'
Config.Target = 'auto'          -- 'auto' | 'ox_target' | 'qb-target' | 'standalone' (מקש E + תפריט מובנה)
Config.Notify = 'auto'          -- 'auto' | 'ox_lib' | 'framework' | 'nui' (התראות מובנות של הסקריפט)

-- שמות המשאבים בשרת. שנו רק אם שיניתם את שם התיקייה של המשאב.
Config.ResourceNames = {
    esx = 'es_extended',
    qbcore = 'qb-core',
    qbox = 'qbx_core',
    ox_lib = 'ox_lib',
    ox_target = 'ox_target',
    qb_target = 'qb-target',
    ox_inventory = 'ox_inventory',
    qb_inventory = 'qb-inventory',
}

-- כמה שניות לחכות בהפעלה למשאב Framework שנמצא בשרת אבל עדיין לא סיים לעלות
Config.FrameworkWaitSeconds = 20

-- מצב Standalone (כשאין Framework / מערכת כסף)
Config.Standalone = {
    -- true = אפשר להזמין, החשבון מוצג ונסגר ללא חיוב כספי (מסומן בבירור כ"ללא חיוב").
    -- false = הזמנות חסומות עד שתוגדר מערכת כסף.
    allowFreeOrders = true,
}

-- ═══════════════════════════════════════════════════════════════════
-- העסק
-- ═══════════════════════════════════════════════════════════════════

Config.Business = {
    name = 'המקום של השייח',       -- שם העסק: מופיע בכותרת התפריט, בקבלה ובכותרת ההתראות
    subtitle = 'טרקלין נרגילות',   -- שורת המשנה מתחת לשם בכותרת התפריט
    job = 'hookah',             -- שם ה-Job של העסק ב-Framework (ESX / QBCore / Qbox)
    openByDefault = true,       -- האם העסק פתוח כשהשרת עולה
    closeWhenNoStaff = false,   -- true = העסק נסגר אוטומטית כשאין עובד במשמרת

    -- מי יכול להיות לקוח:
    --   mode = 'public'  → כולם
    --   mode = 'jobs'    → רק בעלי ה-Jobs שברשימה, לדוגמה { 'hookah', 'police' }
    customerAccess = {
        mode = 'public',
        jobs = {},
    },
}

-- אזור העסק. בדיקות המרחק בשרת משתמשות בו כדי לוודא שהשחקן באמת נמצא בעסק.
Config.Venue = {
    center = vec3(195.0, -935.0, 29.7),
    radius = 30.0,              -- רדיוס העסק במטרים (פעולות לקוח מותרות רק בתוכו)
    renderDistance = 70.0,      -- מאיזה מרחק ליצור NPC, רהיטים ונרגילות אצל השחקן
    snapToGround = true,        -- true = התאמת גובה אוטומטית לקרקע (מומלץ למיקום הדגמה; ב-MLO עדיף false)
}

Config.Blip = {
    enabled = true,
    coords = vec3(195.0, -935.0, 29.7),
    sprite = 93,                -- אייקון במפה
    color = 46,                 -- צבע (46 = זהב)
    scale = 0.85,
    label = "The Sheikh's Place", -- שם במפה. המפה של GTA לא תומכת בעברית — לכן השם באנגלית
}

-- ═══════════════════════════════════════════════════════════════════
-- רהיטים (למיקום בלי MLO). ב-MLO שכבר יש בו שולחנות וכיסאות → enabled = false
-- ═══════════════════════════════════════════════════════════════════

Config.Furniture = {
    enabled = true,
    tableModel = 'prop_table_03',
    chairModel = 'prop_chair_01a',
    chairHeadingOffset = 180.0, -- סיבוב הכיסא ביחס לכיוון הישיבה
    seatZOffset = 0.5,          -- גובה הישיבה מעל הקרקע כש-snapToGround פעיל
}

-- ═══════════════════════════════════════════════════════════════════
-- מארחת בכניסה
-- ═══════════════════════════════════════════════════════════════════

Config.Hostess = {
    model = 'a_f_y_business_01',
    coords = vec4(195.0, -924.0, 29.7, 0.0),
    scenario = 'WORLD_HUMAN_CLIPBOARD', -- אנימציית עמידה (nil = עמידה רגילה)
    interactDistance = 2.0,
    name = 'מאיה',               -- שם המארחת שמופיע בממשק
    gesture = { dict = 'gestures@f@standing@casual', clip = 'gesture_point', duration = 1800 },
    guideSeconds = 25,          -- כמה זמן להציג סימון מעל השולחן שהוקצה
}

-- ═══════════════════════════════════════════════════════════════════
-- מלצרים
-- ═══════════════════════════════════════════════════════════════════
-- כל מלצר משויך לרשימת שולחנות (tables). כשהזמנה יוצאת להגשה, המלצר
-- של אותו שולחן הולך אל השולחן וחוזר לעמדה (אפקט חזותי בלבד, מקומי אצל כל שחקן).

Config.Waiters = {
    {
        model = 's_m_y_waiter_01',
        coords = vec4(191.0, -944.5, 29.7, 0.0),
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
        tables = { 1, 4 },
        name = 'דניאל',
    },
    {
        model = 's_f_y_bartender_01',
        coords = vec4(199.0, -944.5, 29.7, 0.0),
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
        tables = { 2, 3, 5, 6 },
        name = 'נועה',
    },
}

Config.WaiterBehaviour = {
    interactDistance = 2.0,
    walkToTable = true,         -- false = המלצר נשאר בעמדה (ההזמנה עדיין מוגשת כרגיל)
    walkSpeed = 1.0,
    walkTimeout = 20000,        -- אם המלצר לא הגיע תוך הזמן (מכשול) — הוא חוזר לעמדה
    serveAnim = { dict = 'mp_common', clip = 'givetake1_a', duration = 1500 },
}

-- ═══════════════════════════════════════════════════════════════════
-- שולחנות
-- ═══════════════════════════════════════════════════════════════════

Config.TableSettings = {
    reserveTimeout = 180,       -- שניות לשבת אחרי שהמארחת הקצתה שולחן; אחרת השולחן משתחרר
    staffReserveMinutes = 30,   -- כמה זמן נשמרת הזמנת שולחן שעובד יצר ידנית
    cleaningTime = 45,          -- שניות "בניקיון" אחרי שהשולחן התפנה
    allowFreeJoin = false,      -- true = כל אחד יכול לשבת בשולחן תפוס עם מקום פנוי; false = רק מוזמנים
    inviteDistance = 8.0,       -- מרחק מקסימלי להזמנת שחקן לשולחן
    maxPartySize = 6,
    awayDistance = 45.0,        -- מרחק מהעסק שנחשב "עזב"
    awayTimeout = 120,          -- שניות מחוץ לעסק עד ששחקן בלי חשבון פתוח מוסר מהשולחן
    walkoutGrace = 300,         -- שניות מחוץ לעסק עם חשבון פתוח עד שהחשבון מבוטל ונרשם בלוג
    ownerDropBehaviour = 'transfer', -- 'transfer' = הבעלות עוברת לאורח הבא, 'release' = השולחן משתחרר
    interactRadius = 1.8,       -- רדיוס האינטראקציה סביב מרכז השולחן
}

-- seats = מקומות ישיבה: vec4(x, y, z, כיוון) — הכיוון הוא לאן השחקן מסתכל כשהוא יושב.
-- hookahSpots = מקומות להצבת נרגילות ליד השולחן (קובע כמה נרגילות אפשר בשולחן).
-- waiter = אינדקס המלצר (לפי Config.Waiters) — לא חובה, נקבע אוטומטית לפי רשימת tables של המלצרים.
Config.Tables = {
    {
        id = 1, label = 'שולחן 1', capacity = 4, vip = false,
        center = vec3(189.0, -932.0, 29.7),
        seats = {
            vec4(189.95, -932.00, 29.70, 90.0), vec4(189.00, -931.05, 29.70, 180.0),
            vec4(188.05, -932.00, 29.70, 270.0), vec4(189.00, -932.95, 29.70, 0.0),
        },
        hookahSpots = { vec4(189.75, -931.25, 29.70, 0.0), vec4(188.25, -932.75, 29.70, 180.0) },
    },
    {
        id = 2, label = 'שולחן 2', capacity = 4, vip = false,
        center = vec3(195.0, -932.0, 29.7),
        seats = {
            vec4(195.95, -932.00, 29.70, 90.0), vec4(195.00, -931.05, 29.70, 180.0),
            vec4(194.05, -932.00, 29.70, 270.0), vec4(195.00, -932.95, 29.70, 0.0),
        },
        hookahSpots = { vec4(195.75, -931.25, 29.70, 0.0), vec4(194.25, -932.75, 29.70, 180.0) },
    },
    {
        id = 3, label = 'שולחן 3', capacity = 4, vip = false,
        center = vec3(201.0, -932.0, 29.7),
        seats = {
            vec4(201.95, -932.00, 29.70, 90.0), vec4(201.00, -931.05, 29.70, 180.0),
            vec4(200.05, -932.00, 29.70, 270.0), vec4(201.00, -932.95, 29.70, 0.0),
        },
        hookahSpots = { vec4(201.75, -931.25, 29.70, 0.0), vec4(200.25, -932.75, 29.70, 180.0) },
    },
    {
        id = 4, label = 'שולחן 4', capacity = 4, vip = false,
        center = vec3(189.0, -939.0, 29.7),
        seats = {
            vec4(189.95, -939.00, 29.70, 90.0), vec4(189.00, -938.05, 29.70, 180.0),
            vec4(188.05, -939.00, 29.70, 270.0), vec4(189.00, -939.95, 29.70, 0.0),
        },
        hookahSpots = { vec4(189.75, -938.25, 29.70, 0.0), vec4(188.25, -939.75, 29.70, 180.0) },
    },
    {
        id = 5, label = 'שולחן 5', capacity = 4, vip = false,
        center = vec3(195.0, -939.0, 29.7),
        seats = {
            vec4(195.95, -939.00, 29.70, 90.0), vec4(195.00, -938.05, 29.70, 180.0),
            vec4(194.05, -939.00, 29.70, 270.0), vec4(195.00, -939.95, 29.70, 0.0),
        },
        hookahSpots = { vec4(195.75, -938.25, 29.70, 0.0), vec4(194.25, -939.75, 29.70, 180.0) },
    },
    {
        id = 6, label = 'שולחן VIP', capacity = 6, vip = true,
        center = vec3(201.0, -939.5, 29.7),
        seats = {
            vec4(202.25, -939.50, 29.70, 90.0), vec4(201.62, -938.42, 29.70, 150.0),
            vec4(200.38, -938.42, 29.70, 210.0), vec4(199.75, -939.50, 29.70, 270.0),
            vec4(200.38, -940.58, 29.70, 330.0), vec4(201.62, -940.58, 29.70, 30.0),
        },
        hookahSpots = { vec4(201.75, -938.75, 29.70, 0.0), vec4(200.25, -940.25, 29.70, 180.0) },
    },
}

-- ═══════════════════════════════════════════════════════════════════
-- הזמנות
-- ═══════════════════════════════════════════════════════════════════

Config.Orders = {
    -- 'auto'   = מטבח NPC מטפל בכל ההזמנות אוטומטית
    -- 'staff'  = רק עובדים מטפלים בהזמנות (דרך פאנל הניהול)
    -- 'hybrid' = עובדים מטפלים כשיש עובד במשמרת; אם אף עובד לא קיבל את ההזמנה תוך
    --            hybridStaffGrace שניות (או שאין עובדים) — המטבח האוטומטי לוקח אותה
    mode = 'hybrid',
    hybridStaffGrace = 60,
    allowWithoutTable = false,  -- true = אפשר להזמין גם בלי שולחן (הזמנה לבר / טייק-אווי, ללא נרגילות)
    maxLinesPerOrder = 15,      -- מקסימום שורות שונות בהזמנה
    maxQtyPerLine = 10,         -- מקסימום כמות לפריט (אפשר לדרוס לכל פריט עם maxQty)
    maxItemsPerOrder = 25,      -- מקסימום יחידות בהזמנה אחת
    maxActiveOrdersPerPlayer = 3,
    maxOpenBillPerTable = 2500, -- סכום מקסימלי של חשבון פתוח לשולחן לפני שחובה לשלם
    cooldownSeconds = 5,        -- זמן מינימלי בין הזמנות של אותו שחקן
    customerCancelWhileNew = true, -- לקוח יכול לבטל הזמנה שעוד לא התחילה
    autoAcceptDelay = 5,        -- (מטבח אוטומטי) שניות עד שההזמנה עוברת ל"בטיפול"
    defaultPrepTime = 20,       -- זמן הכנה לפריט שאין לו prepTime
    serveTime = 10,             -- שניות ב"בהגשה" עד "הושלמה" (מטבח אוטומטי)
    keepFinishedFor = 900,      -- כמה זמן (שניות) להציג הזמנות שהסתיימו ושולמו
}

-- ═══════════════════════════════════════════════════════════════════
-- תשלומים
-- ═══════════════════════════════════════════════════════════════════

Config.Payments = {
    -- 'on_bill'  = משלמים בסוף ("בקשת חשבון"), כמו במסעדה
    -- 'on_order' = משלמים מיד בעת ההזמנה
    timing = 'on_bill',
    accounts = { 'cash', 'bank' }, -- אמצעי תשלום מותרים: 'cash' ו/או 'bank'
    allowTableBill = true,      -- אפשר לשלם על כל השולחן בבת אחת
    tableBillPayer = 'owner',   -- מי יכול לשלם על כל השולחן: 'owner' (מי שקיבל את השולחן) | 'any_member'
    requireBillBeforeLeave = true, -- אי אפשר לעזוב שולחן עם חשבון אישי פתוח
    serviceChargePercent = 0,   -- דמי שירות באחוזים (0 = ללא)
    tips = { enabled = true, options = { 0, 10, 12, 15 } }, -- אחוזי טיפ לבחירה
    tokenTTL = 120,             -- תוקף בקשת תשלום בשניות (מונע שימוש חוזר)

    -- הפקדת ההכנסות לחשבון העסק (Society). כבוי כברירת מחדל.
    -- system: 'auto' | 'esx_addonaccount' | 'qb-banking' | 'Renewed-Banking'
    -- ב-ESX שם החשבון בדרך כלל 'society_hookah'; ב-QBCore/Qbox בדרך כלל שם ה-Job: 'hookah'.
    society = {
        enabled = false,
        system = 'auto',
        account = 'hookah',
    },
}

-- ═══════════════════════════════════════════════════════════════════
-- מלאי (אופציונלי). כבוי = מלאי בלתי מוגבל.
-- כשמופעל, לכל פריט יכול להיות stock = מספר. מנהל יכול למלא מלאי בפאנל.
-- ═══════════════════════════════════════════════════════════════════

Config.Stock = {
    enabled = false,
    defaultStock = 50,          -- למוצרים בלי stock מוגדר
    restockAmount = 50,         -- כמה מוסיף כפתור "מילוי מלאי"
}

-- ═══════════════════════════════════════════════════════════════════
-- צריכה (אכילה ושתייה) — אנימציות ואביזרים
-- ═══════════════════════════════════════════════════════════════════
-- כל פריט בתפריט מצביע על פרופיל צריכה (consume). אם האנימציה או המודל לא
-- קיימים במשחק, הסקריפט מדלג עליהם בבטחה ומדפיס אזהרה בקונסולה (F8).

Config.ConsumeProfiles = {
    drink_bottle = {
        dict = 'mp_player_intdrink', clip = 'loop_bottle', duration = 5000, flag = 49,
        prop = 'prop_ld_flow_bottle', bone = 18905,
        offset = vec3(0.12, 0.008, 0.03), rotation = vec3(240.0, -60.0, 0.0),
    },
    beer = {
        dict = 'mp_player_intdrink', clip = 'loop_bottle', duration = 5000, flag = 49,
        prop = 'prop_amb_beer_bottle', bone = 18905,
        offset = vec3(0.12, 0.008, 0.03), rotation = vec3(240.0, -60.0, 0.0),
    },
    glass = {
        dict = 'mp_player_intdrink', clip = 'loop_bottle', duration = 5000, flag = 49,
        prop = 'prop_drink_whisky', bone = 18905,
        offset = vec3(0.12, 0.008, 0.03), rotation = vec3(240.0, -60.0, 0.0),
    },
    wine = {
        dict = 'mp_player_intdrink', clip = 'loop_bottle', duration = 5000, flag = 49,
        prop = 'prop_drink_redwine', bone = 18905,
        offset = vec3(0.12, 0.008, 0.03), rotation = vec3(240.0, -60.0, 0.0),
    },
    hot_drink = {
        dict = 'amb@world_human_drinking@coffee@male@idle_a', clip = 'idle_c', duration = 6000, flag = 49,
        prop = 'p_amb_coffeecup_01', bone = 28422,
        offset = vec3(0.0, 0.0, 0.0), rotation = vec3(0.0, 0.0, 0.0),
    },
    food = {
        dict = 'mp_player_inteat@burger', clip = 'mp_player_int_eat_burger', duration = 4500, flag = 49,
        prop = 'prop_cs_burger_01', bone = 18905,
        offset = vec3(0.12, 0.028, 0.001), rotation = vec3(10.0, 175.0, 0.0),
    },
    snack = {
        dict = 'mp_player_inteat@burger', clip = 'mp_player_int_eat_burger', duration = 3500, flag = 49,
        prop = nil, bone = 18905,
        offset = vec3(0.0, 0.0, 0.0), rotation = vec3(0.0, 0.0, 0.0),
    },
}

-- השפעה על רעב/צמא (אופציונלי, כבוי כברירת מחדל).
-- נתמך: ESX עם esx_status, QBCore ו-Qbox (metadata hunger/thirst).
Config.Status = {
    enabled = false,
    -- כמה אחוזים להוסיף לפי פרופיל הצריכה של הפריט (0-100)
    profiles = {
        food = { hunger = 30 },
        snack = { hunger = 12 },
        hot_drink = { thirst = 20 },
        drink_bottle = { thirst = 30 },
        beer = { thirst = 20 },
        glass = { thirst = 15 },
        wine = { thirst = 15 },
    },
}

-- ═══════════════════════════════════════════════════════════════════
-- קטגוריות התפריט (הסדר כאן = הסדר בממשק)
-- ═══════════════════════════════════════════════════════════════════

Config.Categories = {
    { id = 'hookah',  label = 'נרגילות',            icon = 'hookah.svg' },
    { id = 'tea',     label = 'תה וחמים',           icon = 'tea.svg' },
    { id = 'alcohol', label = 'אלכוהול',            icon = 'wine.svg' },
    { id = 'soft',    label = 'משקאות קלים',        icon = 'lemonade.svg' },
    { id = 'snacks',  label = 'פיצוחים ונשנושים',   icon = 'nuts.svg' },
    { id = 'fried',   label = 'מטוגנים',            icon = 'fries.svg' },
}

-- ═══════════════════════════════════════════════════════════════════
-- נרגילות: סוגים וטעמים
-- ═══════════════════════════════════════════════════════════════════
-- מחיר נרגילה = מחיר הסוג + מחיר הטעמים שנבחרו. השרת מחשב את המחיר — תמיד.
-- duration = משך השימוש בשניות. maxFlavors = כמה טעמים אפשר לשלב.
-- allowedFlavors (לא חובה) = רשימת טעמים מותרת לסוג מסוים.
-- prop = מודל הנרגילה בעולם. אין נרגילה במשחק הבסיסי — ברירת המחדל היא מודל
-- חלופי מהמשחק. אם יש לכם מודל נרגילה (stream), כתבו כאן את שמו.

Config.Hookah = {
    useDuration = 7,            -- שניות לכל "שאיפה"
    puffCooldown = 3,           -- המתנה בין שאיפות של אותו שחקן
    requireSeated = true,       -- חייבים לשבת בשולחן כדי לעשן
    defaultProp = 'prop_bong_01',

    flavorChange = { enabled = true, price = 20, refreshDuration = true },
    coalRefresh = { enabled = true, price = 15, extendSeconds = 600, maxRefreshes = 3 },

    -- אנימציית פלג גוף עליון (מתאימה גם בישיבה)
    animation = { dict = 'mp_player_int_uppersmoke', clip = 'mp_player_int_smoke', flag = 49 },
    -- אפקט עשן בנשיפה (מתוך המשחק הבסיסי, לפי התיעוד הרשמי של FiveM)
    particle = {
        enabled = true,
        asset = 'scr_safehouse',
        name = 'scr_sh_bong_smoke',
        scale = 1.0,
        bone = 31086,           -- SKEL_Head
        offset = vec3(-0.025, 0.13, 0.0),
        delay = 3000,           -- מתי (במילישניות מתחילת השאיפה) מופיע העשן
    },

    Types = {
        {
            id = 'hookah_classic', label = 'נרגילה קלאסית',
            description = 'ראש חימר מסורתי, גחלי קוקוס וטעם אחד לבחירה.',
            price = 90, duration = 1200, maxFlavors = 1, image = 'hookah.svg',
            tags = { 'popular' }, prepTime = 25, enabled = true,
        },
        {
            id = 'hookah_premium', label = 'נרגילה פרימיום',
            description = 'ראש פאנל, טבק פרימיום ופיה אישית לכל סועד.',
            price = 140, duration = 1800, maxFlavors = 1, image = 'hookah.svg',
            tags = { 'premium' }, prepTime = 30, enabled = true,
        },
        {
            id = 'hookah_ice', label = 'נרגילת קרח',
            description = 'צינור קירור וקוביות קרח לעשן קריר ועדין במיוחד.',
            price = 120, duration = 1500, maxFlavors = 1, image = 'hookah.svg',
            tags = {}, prepTime = 30, enabled = true,
        },
        {
            id = 'hookah_mix', label = 'נרגילת מיקס',
            description = 'שילוב של עד שני טעמים לבחירתכם.',
            price = 130, duration = 1500, maxFlavors = 2, image = 'hookah.svg',
            tags = { 'popular' }, prepTime = 30, enabled = true,
        },
        {
            id = 'hookah_fruit', label = 'נרגילת פרי',
            description = 'ראש אננס טרי במקום ראש חימר. טעמי פירות בלבד.',
            price = 170, duration = 1500, maxFlavors = 1, image = 'hookah.svg',
            tags = { 'premium' }, prepTime = 40, enabled = true,
            allowedFlavors = { 'watermelon', 'mango', 'peach', 'passion', 'pineapple' },
        },
    },

    Flavors = {
        { id = 'double_apple', label = 'תפוח כפול',     price = 0,  color = '#b5473a', enabled = true },
        { id = 'grape_mint',   label = 'ענבים ונענע',   price = 0,  color = '#6d4a9c', enabled = true },
        { id = 'lemon_mint',   label = 'לימון נענע',    price = 0,  color = '#c8b843', enabled = true },
        { id = 'watermelon',   label = 'אבטיח',         price = 0,  color = '#cf4f6b', enabled = true },
        { id = 'blueberry',    label = 'אוכמניות',      price = 5,  color = '#4a5f9c', enabled = true },
        { id = 'gum_mint',     label = 'מסטיק נענע',    price = 5,  color = '#57a99a', enabled = true },
        { id = 'peach',        label = 'אפרסק',         price = 5,  color = '#e0915a', enabled = true },
        { id = 'mango',        label = 'מנגו',          price = 5,  color = '#e3a93b', enabled = true },
        { id = 'passion',      label = 'פסיפלורה',      price = 8,  color = '#c2793a', enabled = true },
        { id = 'pineapple',    label = 'אננס',          price = 8,  color = '#d8c25a', enabled = true },
        { id = 'forest',       label = 'פירות יער',     price = 8,  color = '#8c3f5f', enabled = true },
        { id = 'cola_ice',     label = 'קולה קרח',      price = 10, color = '#6b4a3a', enabled = true },
    },
}

-- ═══════════════════════════════════════════════════════════════════
-- תפריט מזון ומשקאות
-- ═══════════════════════════════════════════════════════════════════
-- שדות לכל פריט:
--   id          מזהה ייחודי באנגלית (חובה, בלי רווחים)
--   category    מזהה קטגוריה מ-Config.Categories
--   label       שם בתפריט
--   description תיאור קצר
--   price       מחיר (מספר שלם)
--   image       קובץ אייקון מתוך html/assets/icons (לא חובה)
--   prepTime    זמן הכנה בשניות (לא חובה)
--   consume     פרופיל צריכה מ-Config.ConsumeProfiles
--   tags        תגיות לסינון: 'popular', 'spicy', 'vegan', 'premium', 'share'
--   maxQty      מקסימום כמות להזמנה (לא חובה)
--   stock       מלאי התחלתי (רק כש-Config.Stock.enabled)
--   enabled     false = הפריט מוסתר ולא ניתן להזמנה
--   inventory   (לא חובה, פועל רק כש-Config.Inventory אינו 'none'):
--               give    = { name = 'שם_פריט', count = 1 } → הלקוח מקבל פריט אמיתי לאינבנטורי
--               require = { name = 'שם_פריט', count = 1, remove = false } → נדרש פריט כדי להזמין
--               אם הפריט לא קיים באינבנטורי, הסקריפט מתעלם ממנו ומדפיס אזהרה (המוצר עדיין נמכר).

Config.Menu = {
    -- תה וחמים
    { id = 'tea_nana', category = 'tea', label = 'תה נענע', description = 'תה שחור עם נענע טרייה, מוגש בכוס זכוכית.', price = 18, image = 'tea.svg', prepTime = 10, consume = 'hot_drink', tags = { 'popular', 'vegan' }, enabled = true },
    { id = 'tea_herbal', category = 'tea', label = 'תה צמחים', description = 'מרווה, לואיזה ולימונית מגינת הבית.', price = 20, image = 'tea.svg', prepTime = 10, consume = 'hot_drink', tags = { 'vegan' }, enabled = true },
    { id = 'tea_kettle', category = 'tea', label = 'קנקן תה לשולחן', description = 'קנקן גדול לכל השולחן עם צלוחית סוכר וענפי נענע.', price = 45, image = 'kettle.svg', prepTime = 15, consume = 'hot_drink', tags = { 'share', 'vegan' }, maxQty = 3, enabled = true },
    { id = 'coffee_black', category = 'tea', label = 'קפה שחור', description = 'קפה טורקי עם הל, מבושל על פלטה.', price = 15, image = 'coffee.svg', prepTime = 8, consume = 'hot_drink', tags = { 'vegan' }, enabled = true },

    -- אלכוהול
    { id = 'beer_draft', category = 'alcohol', label = 'בירה מהחבית', description = 'חצי ליטר לאגר קר.', price = 28, image = 'beer.svg', prepTime = 5, consume = 'beer', tags = { 'popular' }, enabled = true },
    { id = 'beer_bottle', category = 'alcohol', label = 'בירה בבקבוק', description = 'בקבוק 330 מ"ל.', price = 24, image = 'beer.svg', prepTime = 3, consume = 'beer', tags = {}, enabled = true },
    { id = 'arak_grapefruit', category = 'alcohol', label = 'ערק אשכוליות', description = 'ערק, מיץ אשכוליות סחוט וקרח.', price = 35, image = 'cocktail.svg', prepTime = 6, consume = 'glass', tags = { 'popular' }, enabled = true },
    { id = 'whiskey', category = 'alcohol', label = 'וויסקי', description = 'כוס וויסקי בלנד, נקי או עם קרח.', price = 48, image = 'whiskey.svg', prepTime = 4, consume = 'glass', tags = { 'premium' }, enabled = true },
    { id = 'vodka_energy', category = 'alcohol', label = 'וודקה אנרגיה', description = 'וודקה עם משקה אנרגיה וקרח.', price = 45, image = 'cocktail.svg', prepTime = 5, consume = 'glass', tags = {}, enabled = true },
    { id = 'wine_red', category = 'alcohol', label = 'כוס יין אדום', description = 'יין אדום יבש מהבית.', price = 38, image = 'wine.svg', prepTime = 3, consume = 'wine', tags = {}, enabled = true },
    { id = 'house_cocktail', category = 'alcohol', label = 'קוקטייל הבית', description = 'ג\'ין, פסיפלורה, בזיליקום ולימון.', price = 52, image = 'cocktail.svg', prepTime = 8, consume = 'glass', tags = { 'premium' }, enabled = true },
    { id = 'shots_tray', category = 'alcohol', label = 'מגש צ\'ייסרים', description = 'שישה צ\'ייסרים לשולחן.', price = 75, image = 'shot.svg', prepTime = 5, consume = 'glass', tags = { 'share' }, maxQty = 3, enabled = true },

    -- משקאות קלים
    { id = 'lemonana', category = 'soft', label = 'לימונענע גרוס', description = 'לימונדה עם נענע וקרח גרוס.', price = 18, image = 'lemonade.svg', prepTime = 5, consume = 'glass', tags = { 'popular', 'vegan' }, enabled = true },
    { id = 'cola', category = 'soft', label = 'קולה', description = 'פחית 330 מ"ל.', price = 12, image = 'soda.svg', prepTime = 2, consume = 'drink_bottle', tags = { 'vegan' }, enabled = true },
    { id = 'water', category = 'soft', label = 'מים מינרליים', description = 'בקבוק 500 מ"ל.', price = 8, image = 'water.svg', prepTime = 1, consume = 'drink_bottle', tags = { 'vegan' }, enabled = true },

    -- פיצוחים ונשנושים
    { id = 'nuts_mix', category = 'snacks', label = 'מגש פיצוחים', description = 'גרעינים, בוטנים, פיסטוקים ושקדים קלויים.', price = 30, image = 'nuts.svg', prepTime = 4, consume = 'snack', tags = { 'share', 'vegan', 'popular' }, enabled = true },
    { id = 'pistachio', category = 'snacks', label = 'פיסטוקים', description = 'קערת פיסטוקים קלויים ומלוחים.', price = 32, image = 'nuts.svg', prepTime = 3, consume = 'snack', tags = { 'vegan' }, enabled = true },
    { id = 'edamame', category = 'snacks', label = 'אדממה', description = 'תרמילי סויה מאודים עם מלח גס.', price = 28, image = 'edamame.svg', prepTime = 8, consume = 'snack', tags = { 'vegan' }, enabled = true },
    { id = 'edamame_spicy', category = 'snacks', label = 'אדממה חריפה', description = 'אדממה מוקפצת בשום, צ\'ילי ושמן שומשום.', price = 30, image = 'edamame.svg', prepTime = 10, consume = 'snack', tags = { 'vegan', 'spicy' }, enabled = true },

    -- מטוגנים
    { id = 'fries', category = 'fried', label = 'צ\'יפס', description = 'צ\'יפס פריך עם מלח ים ואיולי.', price = 22, image = 'fries.svg', prepTime = 12, consume = 'food', tags = { 'popular', 'vegan' }, enabled = true },
    { id = 'fries_sweet', category = 'fried', label = 'צ\'יפס בטטה', description = 'בטטה פריכה עם צ\'ילי מתוק.', price = 28, image = 'fries.svg', prepTime = 12, consume = 'food', tags = { 'vegan' }, enabled = true },
    { id = 'onion_rings', category = 'fried', label = 'טבעות בצל', description = 'טבעות בצל בבלילת בירה.', price = 26, image = 'onion_rings.svg', prepTime = 12, consume = 'food', tags = {}, enabled = true },
    { id = 'schnitzelonim', category = 'fried', label = 'שניצלונים', description = 'נתחי חזה עוף בציפוי פריך עם רוטב חרדל-דבש.', price = 38, image = 'schnitzel.svg', prepTime = 15, consume = 'food', tags = { 'popular' }, enabled = true },
    { id = 'wings_bbq', category = 'fried', label = 'כנפיים ברביקיו', description = 'כנפיים פריכות ברוטב ברביקיו מעושן.', price = 45, image = 'wings.svg', prepTime = 18, consume = 'food', tags = {}, enabled = true },
    { id = 'wings_buffalo', category = 'fried', label = 'כנפיים באפלו', description = 'כנפיים חריפות ברוטב באפלו ובצד רוטב שמנת.', price = 45, image = 'wings.svg', prepTime = 18, consume = 'food', tags = { 'spicy' }, enabled = true },
    { id = 'cheese_sticks', category = 'fried', label = 'מקלות גבינה', description = 'מוצרלה בציפוי פריך עם רוטב עגבניות.', price = 32, image = 'cheese_sticks.svg', prepTime = 12, consume = 'food', tags = {}, enabled = true },
    { id = 'cauliflower', category = 'fried', label = 'כרובית מטוגנת', description = 'פרחי כרובית עם טחינה ולימון.', price = 28, image = 'cauliflower.svg', prepTime = 12, consume = 'food', tags = { 'vegan' }, enabled = true },
    { id = 'fried_platter', category = 'fried', label = 'מגש מטוגנים לשולחן', description = 'צ\'יפס, טבעות בצל, שניצלונים ומקלות גבינה — לכל השולחן.', price = 95, image = 'platter.svg', prepTime = 20, consume = 'food', tags = { 'share', 'popular' }, maxQty = 3, enabled = true },
    -- דוגמה לפריט מושבת: לא יופיע בתפריט עד שתשנו enabled = true
    { id = 'falafel', category = 'fried', label = 'כדורי פלאפל', description = 'שישה כדורי פלאפל עם טחינה.', price = 20, image = 'platter.svg', prepTime = 10, consume = 'food', tags = { 'vegan' }, enabled = false },
}

-- ═══════════════════════════════════════════════════════════════════
-- עובדים והרשאות
-- ═══════════════════════════════════════════════════════════════════
-- תפקידים: host (מארחת), waiter (מלצר), cashier (קופה), manager (מנהל)
-- התפקיד נקבע לפי דרגת ה-Job (grade). דרגה שאינה ברשימה מקבלת את התפקיד של
-- הדרגה הגבוהה ביותר שמוגדרת מתחתיה.
-- ניתן גם לתת תפקיד דרך ACE (עובד בכל Framework, כולל Standalone), לדוגמה:
--     add_ace group.admin cyphercity.hookah.manager allow

Config.Staff = {
    requireOnDuty = true,       -- (QBCore/Qbox) רק עובד במשמרת מקבל הרשאות
    bossIsManager = true,       -- isboss ב-QBCore/Qbox = מנהל
    gradeRoles = {
        [0] = 'host',
        [1] = 'waiter',
        [2] = 'cashier',
        [3] = 'manager',
    },
    ace = {
        manager = 'cyphercity.hookah.manager',
        cashier = 'cyphercity.hookah.cashier',
        waiter = 'cyphercity.hookah.waiter',
        host = 'cyphercity.hookah.host',
    },
    -- מה כל תפקיד רשאי לעשות. '*' = הכול.
    permissions = {
        host    = { 'view_tables', 'reserve_table', 'clean_table', 'seat_guest' },
        waiter  = { 'view_tables', 'view_orders', 'update_order', 'take_order', 'clean_table' },
        cashier = { 'view_tables', 'view_orders', 'update_order', 'take_order', 'clean_table', 'cancel_order', 'request_payment', 'view_sales' },
        manager = { '*' },
    },
    panelCommand = 'hookahstaff', -- פקודה לפתיחת פאנל הניהול (רק לעובדים, בתוך העסק)
    panelRequiresVenue = true,
    managementPoint = { coords = vec3(195.0, -945.5, 29.7), radius = 1.2 }, -- עמדת ניהול (nil = ללא)
}

-- ═══════════════════════════════════════════════════════════════════
-- אבטחה
-- ═══════════════════════════════════════════════════════════════════
-- הגבלת קצב: limit בקשות בכל window שניות, לכל שחקן ולכל סוג פעולה.

Config.Security = {
    interactTolerance = 3.0,    -- תוספת מרחק (מטרים) לבדיקות המרחק בשרת
    rateLimits = {
        default      = { limit = 12, window = 10 },
        getState     = { limit = 20, window = 10 },
        requestTable = { limit = 4,  window = 15 },
        sit          = { limit = 6,  window = 10 },
        placeOrder   = { limit = 3,  window = 10 },
        getBill      = { limit = 8,  window = 10 },
        pay          = { limit = 3,  window = 10 },
        hookahAction = { limit = 10, window = 10 },
        consume      = { limit = 6,  window = 10 },
        callWaiter   = { limit = 2,  window = 30 },
        invite       = { limit = 4,  window = 20 },
        staffAction  = { limit = 25, window = 10 },
        invalid      = { limit = 3,  window = 30 }, -- בקשות עם שם לא קיים (ניסיונות פריצה)
    },
    violationsBeforeKick = 0,   -- כמה הפרות אבטחה עד הרחקה אוטומטית (0 = לעולם לא)
}

-- פקודות פיתוח: /hookahcoords מדפיס ומעתיק את המיקום שלכם בפורמט של הקובץ הזה
Config.DevCommands = {
    coords = 'hookahcoords',
}
