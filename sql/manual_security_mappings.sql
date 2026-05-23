INSERT INTO manual_security_mappings (
    source_ticker,
    source_currency,
    canonical_ticker,
    canonical_currency,
    yahoo_symbol,
    price_currency,
    include_in_holdings,
    needs_review,
    notes
)
VALUES
    (
        'AMZN',
        'CAD',
        'AMZN',
        'CAD',
        NULL,
        NULL,
        TRUE,
        FALSE,
        'Amazon CDR position is closed. Keep separate from AMZN USD.'
    ),
    (
        'GOOG',
        'CAD',
        'GOOG',
        'CAD',
        NULL,
        NULL,
        FALSE,
        FALSE,
        'Alphabet CDR activity is closed. Excluded from holdings by user decision.'
    ),
    (
        'GOOG',
        'USD',
        'GOOG',
        'USD',
        'GOOG',
        'USD',
        TRUE,
        FALSE,
        'Alphabet US-listed shares.'
    ),
    (
        'G038487',
        'CAD',
        'GLXY',
        'USD',
        'GLXY',
        'USD',
        TRUE,
        FALSE,
        'Questrade journal code for Galaxy Digital. Confirmed by user as GLXY USD after TSX delisting/journal.'
    ),
    (
        'G038487',
        'USD',
        'GLXY',
        'USD',
        'GLXY',
        'USD',
        TRUE,
        FALSE,
        'Questrade journal code for Galaxy Digital. Confirmed by user as GLXY USD after TSX delisting/journal.'
    ),
    (
        'GLXY',
        'CAD',
        'GLXY',
        'USD',
        'GLXY',
        'USD',
        TRUE,
        FALSE,
        'Galaxy Digital delisted from TSX and shares were journalled to USD version. Confirmed by user.'
    ),
    (
        'GLXY',
        'USD',
        'GLXY',
        'USD',
        'GLXY',
        'USD',
        TRUE,
        FALSE,
        'Galaxy Digital USD-listed shares.'
    ),
    (
        'GLXY.TO',
        'CAD',
        'GLXY',
        'USD',
        'GLXY',
        'USD',
        TRUE,
        FALSE,
        'Galaxy Digital CAD listing/journaled position mapped to USD-listed GLXY. Confirmed by user.'
    ),
    (
        'GLXY',
        '*',
        'GLXY',
        'USD',
        'GLXY',
        'USD',
        TRUE,
        FALSE,
        'Galaxy Digital corporate-action rows with missing currency mapped to GLXY USD. Confirmed by user.'
    ),
    (
        'MAXQ',
        'CAD',
        'MAXQ',
        'CAD',
        'MAXQ.NE',
        'CAD',
        TRUE,
        FALSE,
        'Maritime Launch Services. Yahoo Finance symbol confirmed by user as MAXQ.NE.'
    ),
    (
        'MAXQ.TO',
        'CAD',
        'MAXQ',
        'CAD',
        'MAXQ.NE',
        'CAD',
        TRUE,
        FALSE,
        'Questrade symbol for Maritime Launch Services mapped to user-confirmed Yahoo Finance symbol MAXQ.NE.'
    ),
    (
        'CTH',
        'CAD',
        'CTH',
        'CAD',
        NULL,
        NULL,
        FALSE,
        FALSE,
        'Tiny current CAD position under 50 CAD. Excluded from current holdings and price reporting by user decision.'
    ),
    (
        'MKA',
        'CAD',
        'MKA',
        'CAD',
        NULL,
        NULL,
        FALSE,
        FALSE,
        'Tiny current CAD position under 50 CAD. Excluded from current holdings and price reporting by user decision.'
    ),
    (
        'BTCC.B',
        'CAD',
        'BTCC.B',
        'CAD',
        NULL,
        NULL,
        TRUE,
        FALSE,
        'Closed historical position. Mapping exists to avoid nonstandard-symbol data-quality noise.'
    ),
    (
        'CGL.C',
        'CAD',
        'CGL.C',
        'CAD',
        NULL,
        NULL,
        TRUE,
        FALSE,
        'Closed historical position. Mapping exists to avoid nonstandard-symbol data-quality noise.'
    ),
    (
        'BITF',
        'CAD',
        'KEEL',
        'CAD',
        'KEEL.TO',
        'CAD',
        TRUE,
        FALSE,
        'Bitfarms changed ticker to Keel Infrastructure. User confirmed BITF should map to KEEL.'
    ),
    (
        'BITF',
        '*',
        'KEEL',
        'CAD',
        'KEEL.TO',
        'CAD',
        TRUE,
        FALSE,
        'Bitfarms corporate-action rows with missing currency mapped to KEEL CAD.'
    ),
    (
        'KEEL',
        '*',
        'KEEL',
        'CAD',
        'KEEL.TO',
        'CAD',
        TRUE,
        FALSE,
        'Keel corporate-action rows with missing currency mapped to KEEL CAD.'
    ),
    (
        'KEEL',
        'CAD',
        'KEEL',
        'CAD',
        'KEEL.TO',
        'CAD',
        TRUE,
        FALSE,
        'Keel Infrastructure CAD listing priced with Yahoo Finance KEEL.TO.'
    )
ON CONFLICT (source_ticker, source_currency)
DO UPDATE SET
    canonical_ticker = EXCLUDED.canonical_ticker,
    canonical_currency = EXCLUDED.canonical_currency,
    yahoo_symbol = EXCLUDED.yahoo_symbol,
    price_currency = EXCLUDED.price_currency,
    include_in_holdings = EXCLUDED.include_in_holdings,
    needs_review = EXCLUDED.needs_review,
    notes = EXCLUDED.notes;
