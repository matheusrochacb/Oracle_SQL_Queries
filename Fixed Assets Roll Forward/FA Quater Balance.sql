WITH calendar_dates AS (
        SELECT  fbc.BOOK_TYPE_CODE
                ,fbc.FISCAL_YEAR_NAME
                ,fct.CALENDAR_TYPE
                ,(SELECT fcp2.START_DATE
                        FROM FA_CALENDAR_PERIODS fcp2
                        WHERE fcp2.CALENDAR_TYPE = fct.CALENDAR_TYPE
                        AND fcp2.PERIOD_NAME LIKE ('%' || SUBSTR(:P_Year,3) || '%')
                        AND fcp2.PERIOD_NUM = 1) Start_Date
                ,(SELECT fcp2.START_DATE
                        FROM FA_CALENDAR_PERIODS fcp2
                        WHERE fcp2.CALENDAR_TYPE = fct.CALENDAR_TYPE
                        AND fcp2.PERIOD_NAME LIKE ('%' || SUBSTR(:P_Year,3) || '%')
                        AND fcp2.PERIOD_NUM = 1) Q1_Start_Date
                ,(SELECT fcp2.START_DATE
                        FROM FA_CALENDAR_PERIODS fcp2
                        WHERE fcp2.CALENDAR_TYPE = fct.CALENDAR_TYPE
                        AND fcp2.PERIOD_NAME LIKE ('%' || SUBSTR(:P_Year,3) || '%')
                        AND fcp2.PERIOD_NUM = 4) Q2_Start_Date
                ,(SELECT fcp2.START_DATE
                        FROM FA_CALENDAR_PERIODS fcp2
                        WHERE fcp2.CALENDAR_TYPE = fct.CALENDAR_TYPE
                        AND fcp2.PERIOD_NAME LIKE ('%' || SUBSTR(:P_Year,3) || '%')
                        AND fcp2.PERIOD_NUM = 7) Q3_Start_Date
                ,(SELECT fcp2.START_DATE
                        FROM FA_CALENDAR_PERIODS fcp2
                        WHERE fcp2.CALENDAR_TYPE = fct.CALENDAR_TYPE
                        AND fcp2.PERIOD_NAME LIKE ('%' || SUBSTR(:P_Year,3) || '%')
                        AND fcp2.PERIOD_NUM = 10) Q4_Start_Date
                ,(SELECT fcp2.END_DATE
                        FROM FA_CALENDAR_PERIODS fcp2
                        WHERE fcp2.CALENDAR_TYPE = fct.CALENDAR_TYPE
                        AND fcp2.PERIOD_NAME LIKE ('%' || SUBSTR(:P_Year,3) || '%')
                        AND fcp2.PERIOD_NUM = 12) End_Date
                --,fcp.PERIOD_NAME
        FROM FA_BOOK_CONTROLS fbc
        JOIN FA_CALENDAR_TYPES fct ON fct.FISCAL_YEAR_NAME = fbc.FISCAL_YEAR_NAME
        JOIN FA_CALENDAR_PERIODS fcp ON fcp.CALENDAR_TYPE = fct.CALENDAR_TYPE
        AND fcp.PERIOD_NAME LIKE ('%' || SUBSTR(:P_Year,3) || '%')
        WHERE fbc.BOOK_TYPE_CODE = :P_Asset_Book
        AND ROWNUM = 1
        ORDER BY fbc.BOOK_TYPE_CODE, fbc.FISCAL_YEAR_NAME, fct.CALENDAR_TYPE, fcp.PERIOD_NUM
),
date_params AS (
    SELECT
        cd.Start_Date Start_Date,
        cd.End_Date End_Date,
        cd.Q1_Start_Date Q1_Start_Date,
        cd.Q2_Start_Date Q2_Start_Date,
        cd.Q3_Start_Date Q3_Start_Date,
        cd.Q4_Start_Date Q4_Start_Date
    FROM calendar_dates cd
), 
TRX_DATA AS (
    SELECT  fab.ASSET_NUMBER Asset_Number
            ,fcb.SEGMENT1 Major_Asset_Category 
            ,ROUND(fm.LIFE_IN_MONTHS/12,1) Life_In_Years
            ,fth.TRANSACTION_DATE_ENTERED Trx_Date
            ,NVL((CASE WHEN (fth.TRANSACTION_TYPE_CODE = 'ADDITION' OR fth.TRANSACTION_TYPE_CODE = 'CIP ADDITION')
                    THEN fad.ADJUSTMENT_AMOUNT
            ELSE 0 END),0) Addition_Amount
            ,(CASE WHEN fth.TRANSACTION_TYPE_CODE = 'ADJUSTMENT' AND fad.SOURCE_DEST_CODE IS NULL 
                    THEN fad.ADJUSTMENT_AMOUNT * DECODE(fad.DEBIT_CREDIT_FLAG, 'DR', -1, 'CR', 1)
            WHEN fth.TRANSACTION_TYPE_CODE = 'ADJUSTMENT' AND fad.SOURCE_DEST_CODE IS NOT NULL 
                    THEN fad.ADJUSTMENT_AMOUNT * DECODE(fad.SOURCE_DEST_CODE, 'SOURCE', -1, 'DEST', 1)
            ELSE 0 END) Adjustment_Amount
            ,(CASE WHEN (fth.TRANSACTION_TYPE_CODE = 'PARTIAL RETIREMENT' OR fth.TRANSACTION_TYPE_CODE = 'FULL RETIREMENT')
                    THEN fad.ADJUSTMENT_AMOUNT * -1
            ELSE 0 END) Retired_Amount
            ,(CASE WHEN fth.TRANSACTION_TYPE_CODE = 'REINSTATEMENT'
                    THEN fad.ADJUSTMENT_AMOUNT
            ELSE 0 END) Reinstatement_Amount
            ,fth.TRANSACTION_HEADER_ID Trx_ID

    FROM FA_ADDITIONS_B fab
    JOIN FA_BOOKS bks ON bks.ASSET_ID = fab.ASSET_ID
    AND bks.DATE_INEFFECTIVE IS NULL
    JOIN FA_CATEGORIES_B fcb ON fcb.CATEGORY_ID = fab.ASSET_CATEGORY_ID
    JOIN FA_METHODS fm ON fm.METHOD_ID = bks.METHOD_ID
    JOIN date_params dp ON 1=1
    JOIN FA_TRANSACTION_HEADERS fth ON fth.ASSET_ID = fab.ASSET_ID 
    AND fth.TRANSACTION_DATE_ENTERED >= dp.Start_Date AND fth.TRANSACTION_DATE_ENTERED <= dp.End_Date
    AND fth.TRANSACTION_TYPE_CODE IN ('ADJUSTMENT', 'ADDITION', 'CIP ADDITION', 'PARTIAL RETIREMENT', 'FULL RETIREMENT', 'REINSTATEMENT')
    LEFT JOIN FA_ADJUSTMENTS fad ON fth.ASSET_ID = fad.ASSET_ID AND fth.TRANSACTION_HEADER_ID = fad.TRANSACTION_HEADER_ID
    AND ((fad.SOURCE_TYPE_CODE = 'ADDITION' AND fad.DEBIT_CREDIT_FLAG = 'CR')
            OR (fad.SOURCE_TYPE_CODE = 'ADJUSTMENT' AND fad.SOURCE_DEST_CODE IS NULL AND fad.ADJUSTMENT_TYPE = 'COST CLEARING')
            OR (fad.SOURCE_TYPE_CODE = 'ADJUSTMENT' AND fad.SOURCE_DEST_CODE = 'DEST' AND fad.ADJUSTMENT_TYPE = 'COST')
            OR (fad.SOURCE_TYPE_CODE = 'ADJUSTMENT' AND fad.SOURCE_DEST_CODE = 'SOURCE' AND fad.ADJUSTMENT_TYPE = 'COST')
            OR (fad.SOURCE_TYPE_CODE = 'CIP ADDITION' AND fad.DEBIT_CREDIT_FLAG = 'CR' AND fab.ASSET_TYPE = 'CIP')
            OR (fad.SOURCE_TYPE_CODE = 'RETIREMENT' AND fad.ADJUSTMENT_TYPE = 'COST')
            OR (fad.SOURCE_TYPE_CODE = 'CIP RETIREMENT' AND fad.ADJUSTMENT_TYPE = 'CIP COST'))
    JOIN FA_DISTRIBUTION_HISTORY fdh ON fab.ASSET_ID = fdh.ASSET_ID
    AND fdh.DATE_INEFFECTIVE IS NULL
    AND fdh.DISTRIBUTION_ID = (SELECT MAX(fdh2.DISTRIBUTION_ID)
                                        FROM FA_DISTRIBUTION_HISTORY fdh2
                                        WHERE fdh2.ASSET_ID = fdh.ASSET_ID
                                        AND fdh2.DATE_INEFFECTIVE IS NULL
                                        )
    LEFT JOIN GL_CODE_COMBINATIONS glcc ON glcc.CODE_COMBINATION_ID = fdh.CODE_COMBINATION_ID
    LEFT JOIN FND_FLEX_VALUES_VL ffv ON ffv.FLEX_VALUE = glcc.SEGMENT1
    AND ffv.VALUE_CATEGORY = 'Company COA'
    JOIN date_params dp ON 1=1

    WHERE (:P_Asset_Number IS NULL OR fab.ASSET_NUMBER = :P_Asset_Number)
    AND   (:P_Asset_Book IS NULL OR bks.BOOK_TYPE_CODE = :P_Asset_Book)
    AND   (:P_Company IS NULL OR ffv.FLEX_VALUE = :P_Company)
    AND   (:P_Major_Category IS NULL OR fcb.SEGMENT1 = :P_Major_Category)
    AND   (:P_Life_In_Years IS NULL OR ROUND(fm.LIFE_IN_MONTHS/12,1) = :P_Life_In_Years)
    
    ORDER BY    fab.ASSET_NUMBER 
                ,fcb.SEGMENT1
                ,fm.LIFE_IN_MONTHS
                ,TO_CHAR(fth.TRANSACTION_DATE_ENTERED, 'mm/dd/yyyy')
),
TRX_BEFORE_BEG_BAL AS (
    SELECT  fth1.ASSET_ID
            ,MAX(fth1.TRANSACTION_HEADER_ID) TRANSACTION_HEADER_ID
            ,fth1.TRANSACTION_DATE_ENTERED
    FROM FA_TRANSACTION_HEADERS fth1
    JOIN date_params dp ON 1=1
    WHERE fth1.TRANSACTION_TYPE_CODE IN ('ADJUSTMENT', 'ADDITION', 'CIP ADDITION', 'PARTIAL RETIREMENT', 'FULL RETIREMENT', 'REINSTATEMENT')
    AND fth1.TRANSACTION_DATE_ENTERED = (SELECT MAX(fth2.TRANSACTION_DATE_ENTERED)
                                            FROM FA_TRANSACTION_HEADERS fth2
                                            WHERE fth2.ASSET_ID = fth1.ASSET_ID
                                            AND fth2.TRANSACTION_TYPE_CODE IN ('ADJUSTMENT', 'ADDITION', 'CIP ADDITION', 'PARTIAL RETIREMENT', 'FULL RETIREMENT', 'REINSTATEMENT')
                                            AND fth2.TRANSACTION_DATE_ENTERED < dp.Start_Date)
                                            
    GROUP BY    fth1.ASSET_ID
                ,fth1.TRANSACTION_DATE_ENTERED
),
TRX_BEFORE_END_BAL AS (
    SELECT  fth1.ASSET_ID
            ,MAX(fth1.TRANSACTION_HEADER_ID) TRANSACTION_HEADER_ID
            ,fth1.TRANSACTION_DATE_ENTERED
    FROM FA_TRANSACTION_HEADERS fth1
    JOIN date_params dp ON 1=1
    WHERE fth1.TRANSACTION_TYPE_CODE IN ('ADJUSTMENT', 'ADDITION', 'CIP ADDITION', 'PARTIAL RETIREMENT', 'FULL RETIREMENT', 'REINSTATEMENT')
    AND fth1.TRANSACTION_DATE_ENTERED = (SELECT MAX(fth2.TRANSACTION_DATE_ENTERED)
                                            FROM FA_TRANSACTION_HEADERS fth2
                                            WHERE fth2.ASSET_ID = fth1.ASSET_ID
                                            AND fth2.TRANSACTION_TYPE_CODE IN ('ADJUSTMENT', 'ADDITION', 'CIP ADDITION', 'PARTIAL RETIREMENT', 'FULL RETIREMENT', 'REINSTATEMENT')
                                            AND fth2.TRANSACTION_DATE_ENTERED <= dp.End_Date)
                                            
    GROUP BY    fth1.ASSET_ID
                ,fth1.TRANSACTION_DATE_ENTERED
),
BEG_COSTS AS (
    SELECT  fab.ASSET_NUMBER Asset_Number
            ,fcb.SEGMENT1 Major_Asset_Category 
            ,ROUND(fm.LIFE_IN_MONTHS/12,1) Life_In_Years
            ,bks.COST Beginning_Cost
            
    FROM FA_ADDITIONS_B fab
    JOIN FA_BOOKS bks ON bks.ASSET_ID = fab.ASSET_ID
    JOIN FA_CATEGORIES_B fcb ON fcb.CATEGORY_ID = fab.ASSET_CATEGORY_ID
    JOIN FA_METHODS fm ON fm.METHOD_ID = bks.METHOD_ID
    JOIN TRX_BEFORE_BEG_BAL trxq ON trxq.ASSET_ID = bks.ASSET_ID
    AND trxq.TRANSACTION_HEADER_ID = bks.TRANSACTION_HEADER_ID_IN
    JOIN FA_DISTRIBUTION_HISTORY fdh ON fab.ASSET_ID = fdh.ASSET_ID
    AND fdh.DATE_INEFFECTIVE IS NULL
    AND fdh.DISTRIBUTION_ID = (SELECT MAX(fdh2.DISTRIBUTION_ID)
                                        FROM FA_DISTRIBUTION_HISTORY fdh2
                                        WHERE fdh2.ASSET_ID = fdh.ASSET_ID
                                        AND fdh2.DATE_INEFFECTIVE IS NULL
                                        )
    LEFT JOIN GL_CODE_COMBINATIONS glcc ON glcc.CODE_COMBINATION_ID = fdh.CODE_COMBINATION_ID
    LEFT JOIN FND_FLEX_VALUES_VL ffv ON ffv.FLEX_VALUE = glcc.SEGMENT1
    AND ffv.VALUE_CATEGORY = 'Company COA'

    WHERE (:P_Asset_Number IS NULL OR fab.ASSET_NUMBER = :P_Asset_Number)
    AND   (:P_Asset_Book IS NULL OR bks.BOOK_TYPE_CODE = :P_Asset_Book)
    AND   (:P_Company IS NULL OR ffv.FLEX_VALUE = :P_Company)
    AND   (:P_Major_Category IS NULL OR fcb.SEGMENT1 = :P_Major_Category)
    AND   (:P_Life_In_Years IS NULL OR ROUND(fm.LIFE_IN_MONTHS/12,1) = :P_Life_In_Years)

),
END_COSTS AS (
    SELECT  fab.ASSET_NUMBER Asset_Number
            ,fcb.SEGMENT1 Major_Asset_Category 
            ,ROUND(fm.LIFE_IN_MONTHS/12,1) Life_In_Years
            ,bks.COST Ending_Cost
            
    FROM FA_ADDITIONS_B fab
    JOIN FA_BOOKS bks ON bks.ASSET_ID = fab.ASSET_ID
    JOIN FA_CATEGORIES_B fcb ON fcb.CATEGORY_ID = fab.ASSET_CATEGORY_ID
    JOIN FA_METHODS fm ON fm.METHOD_ID = bks.METHOD_ID
    JOIN TRX_BEFORE_END_BAL trxq ON trxq.ASSET_ID = bks.ASSET_ID
    AND trxq.TRANSACTION_HEADER_ID = bks.TRANSACTION_HEADER_ID_IN
    JOIN FA_DISTRIBUTION_HISTORY fdh ON fab.ASSET_ID = fdh.ASSET_ID
    AND fdh.DATE_INEFFECTIVE IS NULL
    AND fdh.DISTRIBUTION_ID = (SELECT MAX(fdh2.DISTRIBUTION_ID)
                                        FROM FA_DISTRIBUTION_HISTORY fdh2
                                        WHERE fdh2.ASSET_ID = fdh.ASSET_ID
                                        AND fdh2.DATE_INEFFECTIVE IS NULL
                                        )
    LEFT JOIN GL_CODE_COMBINATIONS glcc ON glcc.CODE_COMBINATION_ID = fdh.CODE_COMBINATION_ID
    LEFT JOIN FND_FLEX_VALUES_VL ffv ON ffv.FLEX_VALUE = glcc.SEGMENT1
    AND ffv.VALUE_CATEGORY = 'Company COA'

    WHERE (:P_Asset_Number IS NULL OR fab.ASSET_NUMBER = :P_Asset_Number)
    AND   (:P_Asset_Book IS NULL OR bks.BOOK_TYPE_CODE = :P_Asset_Book)
    AND   (:P_Company IS NULL OR ffv.FLEX_VALUE = :P_Company)
    AND   (:P_Major_Category IS NULL OR fcb.SEGMENT1 = :P_Major_Category)
    AND   (:P_Life_In_Years IS NULL OR ROUND(fm.LIFE_IN_MONTHS/12,1) = :P_Life_In_Years)

),
COMBINED_COSTS AS (
    SELECT bc.Major_Asset_Category
            ,bc.Life_In_Years
            ,SUM(NVL(bc.Beginning_Cost, 0)) Beginning_Cost
            ,SUM(0) Ending_Cost
    FROM BEG_COSTS bc       
    GROUP BY    bc.Major_Asset_Category
                ,bc.Life_In_Years
    UNION ALL
    SELECT ec.Major_Asset_Category
           ,ec.Life_In_Years
           ,SUM(0) Beginning_Cost
           ,SUM(NVL(ec.Ending_Cost, 0)) Ending_Cost
    FROM END_COSTS ec
    GROUP BY    ec.Major_Asset_Category
                ,ec.Life_In_Years
    
),
COMBINED_TRX_DATA AS (
    SELECT  td.Major_Asset_Category
            ,td.Life_In_Years
            ,SUM(0) Beginning_Cost
            ,SUM(0) Ending_Cost
            ,SUM(CASE WHEN td.Trx_Date >= dp.Q1_Start_Date AND td.Trx_Date < dp.Q2_Start_Date THEN td.Addition_Amount ELSE 0 END) Q1_Additions
            ,SUM(CASE WHEN td.Trx_Date >= dp.Q2_Start_Date AND td.Trx_Date < dp.Q3_Start_Date THEN td.Addition_Amount ELSE 0 END) Q2_Additions
            ,SUM(CASE WHEN td.Trx_Date >= dp.Q3_Start_Date AND td.Trx_Date < dp.Q4_Start_Date THEN td.Addition_Amount ELSE 0 END) Q3_Additions
            ,SUM(CASE WHEN td.Trx_Date >= dp.Q4_Start_Date AND td.Trx_Date < dp.End_Date THEN td.Addition_Amount ELSE 0 END) Q4_Additions
            ,SUM(CASE WHEN td.Trx_Date >= dp.Q1_Start_Date AND td.Trx_Date < dp.Q2_Start_Date THEN td.Adjustment_Amount ELSE 0 END) Q1_Adjustments
            ,SUM(CASE WHEN td.Trx_Date >= dp.Q2_Start_Date AND td.Trx_Date < dp.Q3_Start_Date THEN td.Adjustment_Amount ELSE 0 END) Q2_Adjustments
            ,SUM(CASE WHEN td.Trx_Date >= dp.Q3_Start_Date AND td.Trx_Date < dp.Q4_Start_Date THEN td.Adjustment_Amount ELSE 0 END) Q3_Adjustments
            ,SUM(CASE WHEN td.Trx_Date >= dp.Q4_Start_Date AND td.Trx_Date < dp.End_Date THEN td.Adjustment_Amount ELSE 0 END) Q4_Adjustments
            ,(SUM(CASE WHEN td.Trx_Date >= dp.Q1_Start_Date AND td.Trx_Date < dp.Q2_Start_Date THEN td.Retired_Amount ELSE 0 END)
            +  SUM(CASE WHEN td.Trx_Date >= dp.Q1_Start_Date AND td.Trx_Date < dp.Q2_Start_Date THEN td.Reinstatement_Amount ELSE 0 END)) Q1_Retirements
            ,(SUM(CASE WHEN td.Trx_Date >= dp.Q2_Start_Date AND td.Trx_Date < dp.Q3_Start_Date THEN td.Retired_Amount ELSE 0 END)
            +  SUM(CASE WHEN td.Trx_Date >= dp.Q2_Start_Date AND td.Trx_Date < dp.Q3_Start_Date THEN td.Reinstatement_Amount ELSE 0 END)) Q2_Retirements
            ,(SUM(CASE WHEN td.Trx_Date >= dp.Q3_Start_Date AND td.Trx_Date < dp.Q4_Start_Date THEN td.Retired_Amount ELSE 0 END)
            +  SUM(CASE WHEN td.Trx_Date >= dp.Q3_Start_Date AND td.Trx_Date < dp.Q4_Start_Date THEN td.Reinstatement_Amount ELSE 0 END)) Q3_Retirements
            ,(SUM(CASE WHEN td.Trx_Date >= dp.Q4_Start_Date AND td.Trx_Date < dp.End_Date THEN td.Retired_Amount ELSE 0 END)
            +  SUM(CASE WHEN td.Trx_Date >= dp.Q4_Start_Date AND td.Trx_Date < dp.End_Date THEN td.Reinstatement_Amount ELSE 0 END)) Q4_Retirements
    FROM TRX_DATA td
    JOIN date_params dp ON 1=1
    GROUP BY    td.Major_Asset_Category
                ,td.Life_In_Years
    UNION ALL
    SELECT  cc.Major_Asset_Category
            ,cc.Life_In_Years
            ,SUM(cc.Beginning_Cost) Beginning_Cost
            ,SUM(cc.Ending_Cost) Ending_Cost
            ,SUM(0) Q1_Additions
            ,SUM(0) Q2_Additions
            ,SUM(0) Q3_Additions
            ,SUM(0) Q4_Additions

            ,SUM(0) Q1_Adjustments
            ,SUM(0) Q2_Adjustments
            ,SUM(0) Q3_Adjustments
            ,SUM(0) Q4_Adjustments

            ,SUM(0) Q1_Retirements
            ,SUM(0) Q2_Retirements
            ,SUM(0) Q3_Retirements
            ,SUM(0) Q4_Retirements
    FROM COMBINED_COSTS cc
    GROUP BY    cc.Major_Asset_Category
                ,cc.Life_In_Years
),
DEPRN_DATA AS (
        SELECT  fab.ASSET_NUMBER Asset_Number
                ,fcb.SEGMENT1 Major_Asset_Category 
                ,ROUND(fm.LIFE_IN_MONTHS/12,1) Life_In_Years
                ,fdp.PERIOD_OPEN_DATE Row_Date
                ,(CASE WHEN fds.DEPRN_SOURCE_CODE = 'BOOKS' THEN fds.DEPRN_RESERVE
                ELSE fds.SYSTEM_DEPRN_AMOUNT END) * -1 System_Depreciation
                ,(CASE WHEN fds.DEPRN_SOURCE_CODE = 'DEPRN' THEN fds.DEPRN_ADJUSTMENT_AMOUNT
                ELSE 0 END) * -1 Addition_Depreciation
        
        FROM FA_ADDITIONS_B fab
        JOIN FA_BOOKS bks ON bks.ASSET_ID = fab.ASSET_ID
        AND bks.DATE_INEFFECTIVE IS NULL
        JOIN FA_CATEGORIES_B fcb ON fcb.CATEGORY_ID = fab.ASSET_CATEGORY_ID
        JOIN FA_METHODS fm ON fm.METHOD_ID = bks.METHOD_ID
        JOIN date_params dp ON 1=1

        JOIN FA_DEPRN_SUMMARY fds ON fds.ASSET_ID = fab.ASSET_ID
        AND fds.BOOK_TYPE_CODE = bks.BOOK_TYPE_CODE
        JOIN FA_DEPRN_PERIODS fdp ON fdp.PERIOD_COUNTER = fds.PERIOD_COUNTER
        AND fdp.BOOK_TYPE_CODE = fds.BOOK_TYPE_CODE
        AND fdp.PERIOD_OPEN_DATE >= dp.Start_Date AND fdp.PERIOD_OPEN_DATE <= dp.End_Date

        JOIN FA_DISTRIBUTION_HISTORY fdh ON fab.ASSET_ID = fdh.ASSET_ID
        AND fdh.DATE_INEFFECTIVE IS NULL
        AND fdh.DISTRIBUTION_ID = (SELECT MAX(fdh2.DISTRIBUTION_ID)
                                        FROM FA_DISTRIBUTION_HISTORY fdh2
                                        WHERE fdh2.ASSET_ID = fdh.ASSET_ID
                                        AND fdh2.DATE_INEFFECTIVE IS NULL
                                        )
        LEFT JOIN GL_CODE_COMBINATIONS glcc ON glcc.CODE_COMBINATION_ID = fdh.CODE_COMBINATION_ID
        LEFT JOIN FND_FLEX_VALUES_VL ffv ON ffv.FLEX_VALUE = glcc.SEGMENT1
        AND ffv.VALUE_CATEGORY = 'Company COA'

        WHERE (:P_Asset_Number IS NULL OR fab.ASSET_NUMBER = :P_Asset_Number)
        AND   (:P_Asset_Book IS NULL OR bks.BOOK_TYPE_CODE = :P_Asset_Book)
        AND   (:P_Company IS NULL OR ffv.FLEX_VALUE = :P_Company)
        AND   (:P_Major_Category IS NULL OR fcb.SEGMENT1 = :P_Major_Category)
        AND   (:P_Life_In_Years IS NULL OR ROUND(fm.LIFE_IN_MONTHS/12,1) = :P_Life_In_Years)

),
DEPRN_RET_RESERVE AS (
        SELECT  fab.ASSET_NUMBER Asset_Number
                ,fcb.SEGMENT1 Major_Asset_Category 
                ,ROUND(fm.LIFE_IN_MONTHS/12,1) Life_In_Years
                ,fth.TRANSACTION_DATE_ENTERED Row_Date
                ,fad.ADJUSTMENT_AMOUNT Retirement_Reserve

        FROM FA_ADDITIONS_B fab
        JOIN FA_BOOKS bks ON bks.ASSET_ID = fab.ASSET_ID
        AND bks.DATE_INEFFECTIVE IS NULL
        JOIN FA_CATEGORIES_B fcb ON fcb.CATEGORY_ID = fab.ASSET_CATEGORY_ID
        JOIN FA_METHODS fm ON fm.METHOD_ID = bks.METHOD_ID
        JOIN date_params dp ON 1=1

        JOIN FA_RETIREMENTS fr ON fr.ASSET_ID = fab.ASSET_ID
        AND fr.BOOK_TYPE_CODE = bks.BOOK_TYPE_CODE
        AND fr.STATUS = 'PROCESSED'

        JOIN FA_TRANSACTION_HEADERS fth ON fth.ASSET_ID = fab.ASSET_ID
        AND fth.TRANSACTION_HEADER_ID = fr.TRANSACTION_HEADER_ID_IN
        AND fth.TRANSACTION_DATE_ENTERED >= dp.Start_Date AND fth.TRANSACTION_DATE_ENTERED <= dp.End_Date
        JOIN FA_ADJUSTMENTS fad ON fad.ASSET_ID = fab.ASSET_ID
        AND fad.TRANSACTION_HEADER_ID = fr.TRANSACTION_HEADER_ID_IN
        AND (fad.SOURCE_TYPE_CODE = 'RETIREMENT' AND fad.ADJUSTMENT_TYPE = 'RESERVE')

        JOIN FA_DISTRIBUTION_HISTORY fdh ON fab.ASSET_ID = fdh.ASSET_ID
        AND fdh.DATE_INEFFECTIVE IS NULL
        AND fdh.DISTRIBUTION_ID = (SELECT MAX(fdh2.DISTRIBUTION_ID)
                                        FROM FA_DISTRIBUTION_HISTORY fdh2
                                        WHERE fdh2.ASSET_ID = fdh.ASSET_ID
                                        AND fdh2.DATE_INEFFECTIVE IS NULL
                                        )
        LEFT JOIN GL_CODE_COMBINATIONS glcc ON glcc.CODE_COMBINATION_ID = fdh.CODE_COMBINATION_ID
        LEFT JOIN FND_FLEX_VALUES_VL ffv ON ffv.FLEX_VALUE = glcc.SEGMENT1
        AND ffv.VALUE_CATEGORY = 'Company Northgate COA'

        WHERE (:P_Asset_Number IS NULL OR fab.ASSET_NUMBER = :P_Asset_Number)
        AND   (:P_Asset_Book IS NULL OR bks.BOOK_TYPE_CODE = :P_Asset_Book)
        AND   (:P_Company IS NULL OR ffv.FLEX_VALUE = :P_Company)
        AND   (:P_Major_Category IS NULL OR fcb.SEGMENT1 = :P_Major_Category)
        AND   (:P_Life_In_Years IS NULL OR ROUND(fm.LIFE_IN_MONTHS/12,1) = :P_Life_In_Years)
),
COMBINED_DEPRN_DATA_AND_RET_RESERVE AS (
        SELECT  dd.Major_Asset_Category 
                ,dd.Life_In_Years
                ,dd.Row_Date
                ,SUM(dd.System_Depreciation) System_Depreciation
                ,SUM(dd.Addition_Depreciation) Addition_Depreciation
                ,SUM(0) Retirement_Reserve
        FROM DEPRN_DATA dd
        GROUP BY dd.Major_Asset_Category 
                ,dd.Life_In_Years
                ,dd.Row_Date
        UNION ALL
        SELECT  drr.Major_Asset_Category 
                ,drr.Life_In_Years
                ,drr.Row_Date
                ,SUM(0) System_Depreciation
                ,SUM(0) Addition_Depreciation
                ,SUM(drr.Retirement_Reserve) Retirement_Reserve
        FROM DEPRN_RET_RESERVE drr
        GROUP BY drr.Major_Asset_Category 
                ,drr.Life_In_Years
                ,drr.Row_Date

),
DEPRN_BEFORE_BEG_DEPRN AS (
        SELECT  fds1.ASSET_ID
                ,fds1.BOOK_TYPE_CODE
                ,MAX(fdp1.PERIOD_OPEN_DATE) PERIOD_OPEN_DATE
        FROM FA_DEPRN_SUMMARY fds1
        JOIN date_params dp ON 1=1
        JOIN FA_DEPRN_PERIODS fdp1 ON fdp1.BOOK_TYPE_CODE = fds1.BOOK_TYPE_CODE 
        WHERE fdp1.PERIOD_OPEN_DATE = (SELECT MAX(fdp2.PERIOD_OPEN_DATE)
                                                FROM FA_DEPRN_PERIODS fdp2
                                                WHERE fdp2.BOOK_TYPE_CODE = fds1.BOOK_TYPE_CODE 
                                                AND fdp2.PERIOD_COUNTER = fds1.PERIOD_COUNTER
                                                AND fdp2.PERIOD_OPEN_DATE < dp.Start_Date)
        GROUP BY fds1.ASSET_ID
                ,fds1.BOOK_TYPE_CODE

),
BEG_DEPRN AS (
        SELECT  fab.ASSET_NUMBER Asset_Number
                ,fcb.SEGMENT1 Major_Asset_Category 
                ,ROUND(fm.LIFE_IN_MONTHS/12,1) Life_In_Years
                ,fdp.PERIOD_OPEN_DATE Deprn_Date
                ,fds.DEPRN_RESERVE * -1 Beginning_Depreciation
        
        FROM FA_ADDITIONS_B fab
        JOIN FA_BOOKS bks ON bks.ASSET_ID = fab.ASSET_ID
        JOIN FA_CATEGORIES_B fcb ON fcb.CATEGORY_ID = fab.ASSET_CATEGORY_ID
        JOIN FA_METHODS fm ON fm.METHOD_ID = bks.METHOD_ID

        JOIN FA_DEPRN_SUMMARY fds ON fds.ASSET_ID = bks.ASSET_ID
        AND fds.BOOK_TYPE_CODE = bks.BOOK_TYPE_CODE
        JOIN DEPRN_BEFORE_BEG_DEPRN dbbd ON dbbd.ASSET_ID = fds.ASSET_ID
        AND dbbd.BOOK_TYPE_CODE = fds.BOOK_TYPE_CODE
        JOIN FA_DEPRN_PERIODS fdp ON fdp.BOOK_TYPE_CODE = dbbd.BOOK_TYPE_CODE
        AND fdp.PERIOD_COUNTER = fds.PERIOD_COUNTER
        AND fdp.PERIOD_OPEN_DATE = dbbd.PERIOD_OPEN_DATE
        
        JOIN FA_DISTRIBUTION_HISTORY fdh ON fab.ASSET_ID = fdh.ASSET_ID
        AND fdh.DATE_INEFFECTIVE IS NULL
        AND fdh.DISTRIBUTION_ID = (SELECT MAX(fdh2.DISTRIBUTION_ID)
                                        FROM FA_DISTRIBUTION_HISTORY fdh2
                                        WHERE fdh2.ASSET_ID = fdh.ASSET_ID
                                        AND fdh2.DATE_INEFFECTIVE IS NULL
                                        )
        LEFT JOIN GL_CODE_COMBINATIONS glcc ON glcc.CODE_COMBINATION_ID = fdh.CODE_COMBINATION_ID
        LEFT JOIN FND_FLEX_VALUES_VL ffv ON ffv.FLEX_VALUE = glcc.SEGMENT1
        AND ffv.VALUE_CATEGORY = 'Company COA'

        WHERE (:P_Asset_Number IS NULL OR fab.ASSET_NUMBER = :P_Asset_Number)
        AND   (:P_Asset_Book IS NULL OR bks.BOOK_TYPE_CODE = :P_Asset_Book)
        AND   (:P_Company IS NULL OR ffv.FLEX_VALUE = :P_Company)
        AND   (:P_Major_Category IS NULL OR fcb.SEGMENT1 = :P_Major_Category)
        AND   (:P_Life_In_Years IS NULL OR ROUND(fm.LIFE_IN_MONTHS/12,1) = :P_Life_In_Years)

        GROUP BY fab.ASSET_NUMBER 
                ,fcb.SEGMENT1  
                ,fm.LIFE_IN_MONTHS 
                ,fdp.PERIOD_OPEN_DATE 
                ,fds.DEPRN_RESERVE
),
DEPRN_BEFORE_END_DEPRN AS (
        SELECT  fds1.ASSET_ID
                ,fds1.BOOK_TYPE_CODE
                ,MAX(fdp1.PERIOD_OPEN_DATE) PERIOD_OPEN_DATE
        FROM FA_DEPRN_SUMMARY fds1
        JOIN date_params dp ON 1=1
        JOIN FA_DEPRN_PERIODS fdp1 ON fdp1.BOOK_TYPE_CODE = fds1.BOOK_TYPE_CODE 
        WHERE fdp1.PERIOD_OPEN_DATE = (SELECT MAX(fdp2.PERIOD_OPEN_DATE)
                                                FROM FA_DEPRN_PERIODS fdp2
                                                WHERE fdp2.BOOK_TYPE_CODE = fds1.BOOK_TYPE_CODE 
                                                AND fdp2.PERIOD_COUNTER = fds1.PERIOD_COUNTER
                                                AND fdp2.PERIOD_OPEN_DATE <= dp.End_Date)
        GROUP BY fds1.ASSET_ID
                ,fds1.BOOK_TYPE_CODE

),
END_DEPRN AS (
        SELECT  fab.ASSET_NUMBER Asset_Number
                ,fcb.SEGMENT1 Major_Asset_Category 
                ,ROUND(fm.LIFE_IN_MONTHS/12,1) Life_In_Years
                ,fdp.PERIOD_OPEN_DATE Deprn_Date
                ,fds.DEPRN_RESERVE * -1 Ending_Depreciation
        
        FROM FA_ADDITIONS_B fab
        JOIN FA_BOOKS bks ON bks.ASSET_ID = fab.ASSET_ID
        JOIN FA_CATEGORIES_B fcb ON fcb.CATEGORY_ID = fab.ASSET_CATEGORY_ID
        JOIN FA_METHODS fm ON fm.METHOD_ID = bks.METHOD_ID

        JOIN FA_DEPRN_SUMMARY fds ON fds.ASSET_ID = bks.ASSET_ID
        AND fds.BOOK_TYPE_CODE = bks.BOOK_TYPE_CODE
        JOIN DEPRN_BEFORE_END_DEPRN dbed ON dbed.ASSET_ID = fds.ASSET_ID
        AND dbed.BOOK_TYPE_CODE = fds.BOOK_TYPE_CODE
        JOIN FA_DEPRN_PERIODS fdp ON fdp.BOOK_TYPE_CODE = dbed.BOOK_TYPE_CODE
        AND fdp.PERIOD_COUNTER = fds.PERIOD_COUNTER
        AND fdp.PERIOD_OPEN_DATE = dbed.PERIOD_OPEN_DATE
        
        JOIN FA_DISTRIBUTION_HISTORY fdh ON fab.ASSET_ID = fdh.ASSET_ID
        AND fdh.DATE_INEFFECTIVE IS NULL
        AND fdh.DISTRIBUTION_ID = (SELECT MAX(fdh2.DISTRIBUTION_ID)
                                        FROM FA_DISTRIBUTION_HISTORY fdh2
                                        WHERE fdh2.ASSET_ID = fdh.ASSET_ID
                                        AND fdh2.DATE_INEFFECTIVE IS NULL
                                        )
        LEFT JOIN GL_CODE_COMBINATIONS glcc ON glcc.CODE_COMBINATION_ID = fdh.CODE_COMBINATION_ID
        LEFT JOIN FND_FLEX_VALUES_VL ffv ON ffv.FLEX_VALUE = glcc.SEGMENT1
        AND ffv.VALUE_CATEGORY = 'Company COA'

        WHERE (:P_Asset_Number IS NULL OR fab.ASSET_NUMBER = :P_Asset_Number)
        AND   (:P_Asset_Book IS NULL OR bks.BOOK_TYPE_CODE = :P_Asset_Book)
        AND   (:P_Company IS NULL OR ffv.FLEX_VALUE = :P_Company)
        AND   (:P_Major_Category IS NULL OR fcb.SEGMENT1 = :P_Major_Category)
        AND   (:P_Life_In_Years IS NULL OR ROUND(fm.LIFE_IN_MONTHS/12,1) = :P_Life_In_Years)

        GROUP BY fab.ASSET_NUMBER 
                ,fcb.SEGMENT1  
                ,fm.LIFE_IN_MONTHS 
                ,fdp.PERIOD_OPEN_DATE 
                ,fds.DEPRN_RESERVE
),
COMBINED_BEG_END_DEPRN AS (
        SELECT  bd.Major_Asset_Category
                ,bd.Life_In_Years
                ,SUM(bd.Beginning_Depreciation) Beginning_Depreciation
                ,SUM(0) Ending_Depreciation
        FROM BEG_DEPRN bd
        GROUP BY bd.Major_Asset_Category
                ,bd.Life_In_Years
        UNION ALL
        SELECT  ed.Major_Asset_Category
                ,ed.Life_In_Years
                ,SUM(0) Beginning_Depreciation
                ,SUM(ed.Ending_Depreciation) Ending_Depreciation
        FROM END_DEPRN ed
        GROUP BY ed.Major_Asset_Category
                ,ed.Life_In_Years
),
COMBINED_DEPRN_DATA AS (
    SELECT  cddrr.Major_Asset_Category
            ,cddrr.Life_In_Years
            ,SUM(0) Beginning_Depreciation
            ,SUM(0) Ending_Depreciation
            ,SUM(CASE WHEN cddrr.Row_Date >= dp.Q1_Start_Date AND cddrr.Row_Date < dp.Q2_Start_Date THEN cddrr.System_Depreciation ELSE 0 END) Q1_Depreciation
            ,SUM(CASE WHEN cddrr.Row_Date >= dp.Q2_Start_Date AND cddrr.Row_Date < dp.Q3_Start_Date THEN cddrr.System_Depreciation ELSE 0 END) Q2_Depreciation
            ,SUM(CASE WHEN cddrr.Row_Date >= dp.Q3_Start_Date AND cddrr.Row_Date < dp.Q4_Start_Date THEN cddrr.System_Depreciation ELSE 0 END) Q3_Depreciation
            ,SUM(CASE WHEN cddrr.Row_Date >= dp.Q4_Start_Date AND cddrr.Row_Date < dp.End_Date THEN cddrr.System_Depreciation ELSE 0 END) Q4_Depreciation

            ,SUM(CASE WHEN cddrr.Row_Date >= dp.Q1_Start_Date AND cddrr.Row_Date < dp.Q2_Start_Date THEN cddrr.Addition_Depreciation ELSE 0 END) Q1_Addition_Depreciation
            ,SUM(CASE WHEN cddrr.Row_Date >= dp.Q2_Start_Date AND cddrr.Row_Date < dp.Q3_Start_Date THEN cddrr.Addition_Depreciation ELSE 0 END) Q2_Addition_Depreciation
            ,SUM(CASE WHEN cddrr.Row_Date >= dp.Q3_Start_Date AND cddrr.Row_Date < dp.Q4_Start_Date THEN cddrr.Addition_Depreciation ELSE 0 END) Q3_Addition_Depreciation
            ,SUM(CASE WHEN cddrr.Row_Date >= dp.Q4_Start_Date AND cddrr.Row_Date < dp.End_Date THEN cddrr.Addition_Depreciation ELSE 0 END) Q4_Addition_Depreciation

            ,(SUM(CASE WHEN cddrr.Row_Date >= dp.Q1_Start_Date AND cddrr.Row_Date < dp.Q2_Start_Date THEN cddrr.Retirement_Reserve ELSE 0 END)) Q1_Retirement_Depreciation
            ,(SUM(CASE WHEN cddrr.Row_Date >= dp.Q2_Start_Date AND cddrr.Row_Date < dp.Q3_Start_Date THEN cddrr.Retirement_Reserve ELSE 0 END)) Q2_Retirement_Depreciation
            ,(SUM(CASE WHEN cddrr.Row_Date >= dp.Q3_Start_Date AND cddrr.Row_Date < dp.Q4_Start_Date THEN cddrr.Retirement_Reserve ELSE 0 END)) Q3_Retirement_Depreciation
            ,(SUM(CASE WHEN cddrr.Row_Date >= dp.Q4_Start_Date AND cddrr.Row_Date < dp.End_Date THEN cddrr.Retirement_Reserve ELSE 0 END)) Q4_Retirement_Depreciation
    FROM COMBINED_DEPRN_DATA_AND_RET_RESERVE cddrr
    JOIN date_params dp ON 1=1
    GROUP BY    cddrr.Major_Asset_Category
                ,cddrr.Life_In_Years
    UNION ALL
    SELECT  cbed.Major_Asset_Category
            ,cbed.Life_In_Years
            ,SUM(cbed.Beginning_Depreciation) Beginning_Depreciation
            ,SUM(cbed.Ending_Depreciation) Ending_Depreciation
            ,SUM(0) Q1_Depreciation
            ,SUM(0) Q2_Depreciation
            ,SUM(0) Q3_Depreciation
            ,SUM(0) Q4_Depreciation

            ,SUM(0) Q1_Addition_Depreciation
            ,SUM(0) Q2_Addition_Depreciation
            ,SUM(0) Q3_Addition_Depreciation
            ,SUM(0) Q4_Addition_Depreciation

            ,SUM(0) Q1_Retirement_Depreciation
            ,SUM(0) Q2_Retirement_Depreciation
            ,SUM(0) Q3_Retirement_Depreciation
            ,SUM(0) Q4_Retirement_Depreciation
    FROM COMBINED_BEG_END_DEPRN cbed
    GROUP BY    cbed.Major_Asset_Category
                ,cbed.Life_In_Years
),
ALL_DATA_COMBINED AS (
        SELECT  ctd.Major_Asset_Category
                ,ctd.Life_in_Years

                ,SUM(ctd.Beginning_Cost) Beginning_Balance
                ,SUM(ctd.Ending_Cost) Ending_Balance

                ,SUM(ctd.Q1_Additions) Q1_Additions
                ,SUM(ctd.Q1_Retirements) Q1_Retirements
                ,SUM(ctd.Q1_Adjustments) Q1_Adjustments
                
                ,SUM(ctd.Q2_Additions) Q2_Additions
                ,SUM(ctd.Q2_Retirements) Q2_Retirements
                ,SUM(ctd.Q2_Adjustments) Q2_Adjustments
                
                ,SUM(ctd.Q3_Additions) Q3_Additions
                ,SUM(ctd.Q3_Retirements) Q3_Retirements
                ,SUM(ctd.Q3_Adjustments) Q3_Adjustments
                
                ,SUM(ctd.Q4_Additions) Q4_Additions
                ,SUM(ctd.Q4_Retirements) Q4_Retirements
                ,SUM(ctd.Q4_Adjustments) Q4_Adjustments

                ,SUM(0) Beginning_Depreciation
                ,SUM(0) Ending_Depreciation
                ,SUM(0) Q1_Depreciation
                ,SUM(0) Q2_Depreciation
                ,SUM(0) Q3_Depreciation
                ,SUM(0) Q4_Depreciation

                ,SUM(0) Q1_Addition_Depreciation
                ,SUM(0) Q2_Addition_Depreciation
                ,SUM(0) Q3_Addition_Depreciation
                ,SUM(0) Q4_Addition_Depreciation

                ,SUM(0) Q1_Retirement_Depreciation
                ,SUM(0) Q2_Retirement_Depreciation
                ,SUM(0) Q3_Retirement_Depreciation
                ,SUM(0) Q4_Retirement_Depreciation
       
        FROM COMBINED_TRX_DATA ctd
        GROUP BY ctd.Major_Asset_Category
                ,ctd.Life_in_Years
        UNION ALL
        SELECT  cdd.Major_Asset_Category
                ,cdd.Life_in_Years

                ,SUM(0) Beginning_Balance
                ,SUM(0) Ending_Balance

                ,SUM(0) Q1_Additions
                ,SUM(0) Q1_Retirements
                ,SUM(0) Q1_Adjustments
                
                ,SUM(0) Q2_Additions
                ,SUM(0) Q2_Retirements
                ,SUM(0) Q2_Adjustments
                
                ,SUM(0) Q3_Additions
                ,SUM(0) Q3_Retirements
                ,SUM(0) Q3_Adjustments
                
                ,SUM(0) Q4_Additions
                ,SUM(0) Q4_Retirements
                ,SUM(0) Q4_Adjustments

                ,SUM(cdd.Beginning_Depreciation) Beginning_Depreciation
                ,SUM(cdd.Ending_Depreciation) Ending_Depreciation

                ,SUM(cdd.Q1_Depreciation) Q1_Depreciation
                ,SUM(cdd.Q2_Depreciation) Q2_Depreciation
                ,SUM(cdd.Q3_Depreciation) Q3_Depreciation
                ,SUM(cdd.Q4_Depreciation) Q4_Depreciation

                ,SUM(cdd.Q1_Addition_Depreciation) Q1_Addition_Depreciation
                ,SUM(cdd.Q2_Addition_Depreciation) Q2_Addition_Depreciation
                ,SUM(cdd.Q3_Addition_Depreciation) Q3_Addition_Depreciation
                ,SUM(cdd.Q4_Addition_Depreciation) Q4_Addition_Depreciation

                ,SUM(cdd.Q1_Retirement_Depreciation) Q1_Retirement_Depreciation
                ,SUM(cdd.Q2_Retirement_Depreciation) Q2_Retirement_Depreciation
                ,SUM(cdd.Q3_Retirement_Depreciation) Q3_Retirement_Depreciation
                ,SUM(cdd.Q4_Retirement_Depreciation) Q4_Retirement_Depreciation
        FROM COMBINED_DEPRN_DATA cdd
        GROUP BY cdd.Major_Asset_Category
                ,cdd.Life_in_Years
)

SELECT  Major_Asset_Category
       ,Life_in_Years

       ,SUM(Beginning_Balance) Beginning_Balance
       ,SUM(Ending_Balance) Ending_Balance

       ,(SUM(Q1_Additions) + SUM(Q1_Adjustments) + SUM(Q1_Retirements)) Q1 
       ,SUM(Q1_Additions) Q1_Additions
       ,SUM(Q1_Retirements) Q1_Retirements
       ,SUM(Q1_Adjustments) Q1_Adjustments

       ,(SUM(Q2_Additions) + SUM(Q2_Adjustments) + SUM(Q2_Retirements)) Q2 
       ,SUM(Q2_Additions) Q2_Additions
       ,SUM(Q2_Retirements) Q2_Retirements
       ,SUM(Q2_Adjustments) Q2_Adjustments
       
       ,(SUM(Q3_Additions) + SUM(Q3_Adjustments) + SUM(Q3_Retirements)) Q3
       ,SUM(Q3_Additions) Q3_Additions
       ,SUM(Q3_Retirements) Q3_Retirements
       ,SUM(Q3_Adjustments) Q3_Adjustments
       
       ,(SUM(Q4_Additions) + SUM(Q4_Adjustments) + SUM(Q4_Retirements)) Q4
       ,SUM(Q4_Additions) Q4_Additions
       ,SUM(Q4_Retirements) Q4_Retirements
       ,SUM(Q4_Adjustments) Q4_Adjustments

       ,SUM(Beginning_Depreciation) Beginning_Depreciation
       ,SUM(Ending_Depreciation) Ending_Depreciation

       ,(SUM(Q1_Depreciation) + SUM(Q1_Addition_Depreciation) + SUM(Q1_Retirement_Depreciation)) Q1_Depreciation
       ,(SUM(Q2_Depreciation) + SUM(Q2_Addition_Depreciation) + SUM(Q2_Retirement_Depreciation)) Q2_Depreciation
       ,(SUM(Q3_Depreciation) + SUM(Q3_Addition_Depreciation) + SUM(Q3_Retirement_Depreciation)) Q3_Depreciation
       ,(SUM(Q4_Depreciation) + SUM(Q4_Addition_Depreciation) + SUM(Q4_Retirement_Depreciation)) Q4_Depreciation

       ,SUM(Q1_Addition_Depreciation) Q1_Addition_Depreciation
        ,SUM(Q2_Addition_Depreciation) Q2_Addition_Depreciation
        ,SUM(Q3_Addition_Depreciation) Q3_Addition_Depreciation
        ,SUM(Q4_Addition_Depreciation) Q4_Addition_Depreciation

        ,SUM(Q1_Retirement_Depreciation) Q1_Retirement_Depreciation
        ,SUM(Q2_Retirement_Depreciation) Q2_Retirement_Depreciation
        ,SUM(Q3_Retirement_Depreciation) Q3_Retirement_Depreciation
        ,SUM(Q4_Retirement_Depreciation) Q4_Retirement_Depreciation
       
    FROM ALL_DATA_COMBINED
    GROUP BY Major_Asset_Category
            ,Life_in_Years
    ORDER BY Major_Asset_Category, Life_in_Years
        