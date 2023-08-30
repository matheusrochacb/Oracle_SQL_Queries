WITH cost_variation AS 
(
    SELECT  Asset_Book
        ,Asset_Number
        ,Asset_Type
        --,Transaction_Month
        ,Store_Number
        ,Store_Location
        ,Period_Month
        ,Period_Name
        ,SUM(Additions + Adjustments + Retirements) Cost_Variation
FROM (SELECT  fb.BOOK_TYPE_CODE Asset_Book
        ,fab.ASSET_NUMBER Asset_Number
        ,fab.ASSET_TYPE Asset_Type
        ,EXTRACT(MONTH FROM fth.TRANSACTION_DATE_ENTERED) Transaction_Month
        ,ffv.FLEX_VALUE Store_Number
        ,ffv.DESCRIPTION Store_Location
        ,SUM(DISTINCT NVL((SELECT SUM(fad.ADJUSTMENT_AMOUNT)
                            FROM FA_ADJUSTMENTS fad
                            WHERE fad.ASSET_ID = fab.ASSET_ID
                            AND fad.DISTRIBUTION_ID = fdh.DISTRIBUTION_ID
                            AND fad.TRANSACTION_HEADER_ID = fth.TRANSACTION_HEADER_ID
                            AND fad.SOURCE_TYPE_CODE IN ('ADDITION', 'CIP ADDITION')
                            AND fad.DEBIT_CREDIT_FLAG = 'CR'
                            AND fth.TRANSACTION_DATE_ENTERED BETWEEN (:P_FROM_DATE) AND (:P_TO_DATE))
                            , 0)
        ) Additions
        ,(SUM(DISTINCT NVL((SELECT SUM(fad.ADJUSTMENT_AMOUNT * DECODE(fad.SOURCE_DEST_CODE, 'DEST', 1, 'SOURCE', -1))
                            FROM FA_ADJUSTMENTS fad
                            WHERE fad.ASSET_ID = fab.ASSET_ID
                            AND fad.DISTRIBUTION_ID = fdh.DISTRIBUTION_ID
                            AND fad.TRANSACTION_HEADER_ID = fth.TRANSACTION_HEADER_ID
                            AND fad.SOURCE_TYPE_CODE IN ('ADJUSTMENT', 'CIP ADJUSTMENT')
                            AND fad.ADJUSTMENT_TYPE IN ('COST', 'CIP COST')
                            AND fad.SOURCE_DEST_CODE IS NOT NULL
                            AND fth.TRANSACTION_DATE_ENTERED BETWEEN (:P_FROM_DATE) AND (:P_TO_DATE))
                            , 0)
            ) + SUM(DISTINCT NVL((SELECT SUM(fad.ADJUSTMENT_AMOUNT * DECODE(fad.DEBIT_CREDIT_FLAG, 'DR', -1, 'CR', 1))
                            FROM FA_ADJUSTMENTS fad
                            WHERE fad.ASSET_ID = fab.ASSET_ID
                            AND fad.DISTRIBUTION_ID = fdh.DISTRIBUTION_ID
                            AND fad.TRANSACTION_HEADER_ID = fth.TRANSACTION_HEADER_ID
                            AND fad.SOURCE_TYPE_CODE IN ('ADJUSTMENT', 'CIP ADJUSTMENT')
                            AND fad.ADJUSTMENT_TYPE IN ('COST CLEARING')
                            AND fad.SOURCE_DEST_CODE IS NULL
                            AND fth.TRANSACTION_DATE_ENTERED BETWEEN (:P_FROM_DATE) AND (:P_TO_DATE))
                            , 0)
        )) Adjustments
        ,SUM(DISTINCT NVL((SELECT SUM(fad.ADJUSTMENT_AMOUNT * DECODE(fad.DEBIT_CREDIT_FLAG, 'DR', -1, 'CR', 1))
                            FROM FA_ADJUSTMENTS fad
                            WHERE fad.ASSET_ID = fab.ASSET_ID
                            AND fad.DISTRIBUTION_ID = fdh.DISTRIBUTION_ID
                            AND fad.TRANSACTION_HEADER_ID = fth.TRANSACTION_HEADER_ID
                            AND fad.SOURCE_TYPE_CODE IN ('RETIREMENT')
                            AND fad.ADJUSTMENT_TYPE IN ('NBV RETIRED')
                            AND fth.TRANSACTION_DATE_ENTERED BETWEEN (:P_FROM_DATE) AND (:P_TO_DATE))
                            , 0)
        ) Retirements
        ,fdj.PERIOD_COUNTER_ADJUSTED Period_Counter
        ,fdp.PERIOD_NAME Period_Name
        ,SUBSTR(fdp.PERIOD_NAME, 1, INSTR(fdp.PERIOD_NAME,'-', 1, 1) - 1) Period_Month

FROM  FA_ADDITIONS_B fab
    LEFT JOIN FA_BOOKS fb ON fab.ASSET_ID = fb.ASSET_ID
    LEFT JOIN FA_TRANSACTION_HEADERS fth ON fab.ASSET_ID = fth.ASSET_ID
    LEFT JOIN FA_DISTRIBUTION_HISTORY fdh ON fab.ASSET_ID = fdh.ASSET_ID
    LEFT JOIN GL_CODE_COMBINATIONS gcc ON fdh.CODE_COMBINATION_ID = gcc.CODE_COMBINATION_ID
    LEFT JOIN FND_FLEX_VALUES_VL ffv ON gcc.SEGMENT2 = ffv.FLEX_VALUE
    LEFT JOIN FA_ADJUSTMENTS fdj ON fdj.DISTRIBUTION_ID = fdh.DISTRIBUTION_ID
    AND fdj.TRANSACTION_HEADER_ID = fth.TRANSACTION_HEADER_ID
    LEFT JOIN FA_DEPRN_PERIODS fdp ON fdp.PERIOD_COUNTER = fdj.PERIOD_COUNTER_ADJUSTED
    
WHERE fb.DATE_INEFFECTIVE IS NULL
--AND fdp.PERIOD_NAME LIKE 'P%'
AND (:P_Asset_Book IS NULL OR fb.BOOK_TYPE_CODE = :P_Asset_Book)
AND (LEAST(:P_Location) IS NULL OR ffv.FLEX_VALUE IN (:P_Location))
AND fth.TRANSACTION_DATE_ENTERED BETWEEN (:P_FROM_DATE) AND (:P_TO_DATE)

GROUP BY fb.BOOK_TYPE_CODE
         ,fab.ASSET_NUMBER
         ,fab.ASSET_TYPE 
         ,fth.TRANSACTION_DATE_ENTERED
         ,ffv.FLEX_VALUE
         ,ffv.DESCRIPTION
         ,fdj.PERIOD_COUNTER_ADJUSTED
         ,fdp.PERIOD_NAME

) 
GROUP BY Asset_Book
        ,Asset_Number
        ,Asset_Type
        --,Transaction_Month
        ,Store_Number
        ,Store_Location
        ,Period_Month
        ,Period_Name

ORDER BY Asset_Book
        ,Asset_Type
        ,Asset_Number
       -- ,Transaction_Month
        ,Store_Number

), deprn_variation AS
(
    SELECT  Asset_Book
        ,Asset_Number
        ,Asset_Type
        --,Transaction_Month
        ,Store_Number
        ,Store_Location
        ,Period_Month
        ,Period_Name
        ,SUM(Dprn_Amount_Per_Period) Dprn_Variation
FROM (SELECT  fb.BOOK_TYPE_CODE Asset_Book
        ,fab.ASSET_NUMBER Asset_Number
        ,fab.ASSET_TYPE Asset_Type
        --,EXTRACT(MONTH FROM fds.DEPRN_RUN_DATE) Transaction_Month
        ,ffv.FLEX_VALUE Store_Number
        ,ffv.DESCRIPTION Store_Location
        ,fds.PERIOD_COUNTER Period_Counter
        ,fdp.PERIOD_NAME Period_Name
        ,fds.DEPRN_AMOUNT Dprn_Amount_Per_Period
        ,SUBSTR(fdp.PERIOD_NAME, 1, INSTR(fdp.PERIOD_NAME,'-', 1, 1) - 1) Period_Month
        /*,fds.YTD_DEPRN
        ,fds.DEPRN_RESERVE
        ,fds.REVAL_RESERVE
        ,fds.IMPAIRMENT_AMOUNT
        ,fds.IMPAIRMENT_RESERVE
        ,fds.DEPRN_ADJUSTMENT_AMOUNT
        ,fds.BONUS_DEPRN_ADJUSTMENT_AMOUNT*/

FROM  FA_ADDITIONS_B fab
    LEFT JOIN FA_BOOKS fb ON fab.ASSET_ID = fb.ASSET_ID
    LEFT JOIN FA_DEPRN_SUMMARY fds ON fab.ASSET_ID = fds.ASSET_ID
    LEFT JOIN FA_DISTRIBUTION_HISTORY fdh ON fab.ASSET_ID = fdh.ASSET_ID
    LEFT JOIN GL_CODE_COMBINATIONS gcc ON fdh.CODE_COMBINATION_ID = gcc.CODE_COMBINATION_ID
    LEFT JOIN FND_FLEX_VALUES_VL ffv ON gcc.SEGMENT2 = ffv.FLEX_VALUE
    LEFT JOIN FA_DEPRN_PERIODS fdp ON fdp.PERIOD_COUNTER = fds.PERIOD_COUNTER
    
WHERE fb.DATE_INEFFECTIVE IS NULL
--AND fdp.PERIOD_NAME LIKE 'P%'
--AND fds.DEPRN_SOURCE_CODE = 'DEPRN'
AND (:P_Asset_Book IS NULL OR fb.BOOK_TYPE_CODE = :P_Asset_Book)
AND (LEAST(:P_Location) IS NULL OR ffv.FLEX_VALUE IN (:P_Location))
AND fds.DEPRN_RUN_DATE BETWEEN (:P_FROM_DATE) AND (:P_TO_DATE)

GROUP BY fb.BOOK_TYPE_CODE
         ,fab.ASSET_NUMBER
         ,fab.ASSET_TYPE 
         --,fds.DEPRN_RUN_DATE
         ,ffv.FLEX_VALUE
         ,ffv.DESCRIPTION
         ,fds.PERIOD_COUNTER 
         ,fdp.PERIOD_NAME 
         ,fds.DEPRN_AMOUNT
         /*,fds.YTD_DEPRN
         ,fds.DEPRN_RESERVE
         ,fds.REVAL_RESERVE
         ,fds.IMPAIRMENT_AMOUNT
         ,fds.IMPAIRMENT_RESERVE
         ,fds.DEPRN_ADJUSTMENT_AMOUNT
        ,fds.BONUS_DEPRN_ADJUSTMENT_AMOUNT*/

) 
GROUP BY Asset_Book
        ,Asset_Number
        ,Asset_Type
        --,Transaction_Month
        ,Store_Number
        ,Store_Location
        ,Period_Month
        ,Period_Name
        
ORDER BY Asset_Book
        ,Asset_Type
        ,Asset_Number
        --,Transaction_Month
        ,Store_Number
)

SELECT  dv.Asset_Book
        ,dv.Store_Number
        ,dv.Store_Location
        --,dv.Asset_Number
        ,dv.Period_Month
        ,dv.Period_Name
        ,SUM(DISTINCT NVL(cv.Cost_Variation,0)) Cost_Variation
        ,SUM(DISTINCT NVL(dv.Dprn_Variation,0)) Dprn_Variation
FROM deprn_variation dv
LEFT JOIN cost_variation cv ON cv.Asset_Book = dv.Asset_Book
AND cv.Asset_Number = dv.Asset_Number
AND cv.Asset_Type = dv.Asset_Type
AND cv.Store_Number = dv.Store_Number
AND cv.Store_Location = dv.Store_Location
AND cv.Period_Name = dv.Period_Name

GROUP BY dv.Asset_Book 
        ,dv.Store_Number
        ,dv.Store_Location
        --,dv.Asset_Number
        ,dv.Period_Month
        ,dv.Period_Name
ORDER BY dv.Asset_Book 
        ,dv.Store_Number
        ,dv.Store_Location
        --,dv.Asset_Number
        ,dv.Period_Name