SELECT  Asset_Book
        --,Asset_Number
        --,Asset_Type
        --,Transaction_Month
        ,Store_Number
        ,Store_Location
        ,SUM(Additions+Adjustments+Retirements) - SUM(Beginning_Deprn) - SUM(Beginning_Impair_Deprn) Beginning_NVB
FROM (SELECT DISTINCT fb.BOOK_TYPE_CODE Asset_Book
        ,fab.ASSET_NUMBER Asset_Number
        ,fab.ASSET_TYPE Asset_Type
        --,EXTRACT(MONTH FROM fds.DEPRN_RUN_DATE) Transaction_Month
        ,ffv.FLEX_VALUE Store_Number
        ,ffv.DESCRIPTION Store_Location
        ,SUM(DISTINCT NVL((SELECT SUM(fad.ADJUSTMENT_AMOUNT)
                            FROM FA_ADJUSTMENTS fad
                            WHERE fad.ASSET_ID = fab.ASSET_ID
                            AND fad.DISTRIBUTION_ID = fdh.DISTRIBUTION_ID
                            AND fad.TRANSACTION_HEADER_ID = fth.TRANSACTION_HEADER_ID
                            AND fad.SOURCE_TYPE_CODE IN ('ADDITION', 'CIP ADDITION')
                            AND fad.DEBIT_CREDIT_FLAG = 'CR'
                            AND fth.TRANSACTION_DATE_ENTERED <= (:P_FROM_DATE))
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
                            AND fth.TRANSACTION_DATE_ENTERED <= (:P_FROM_DATE))
                            , 0)
            ) + SUM(DISTINCT NVL((SELECT SUM(fad.ADJUSTMENT_AMOUNT * DECODE(fad.DEBIT_CREDIT_FLAG, 'DR', -1, 'CR', 1))
                            FROM FA_ADJUSTMENTS fad
                            WHERE fad.ASSET_ID = fab.ASSET_ID
                            AND fad.DISTRIBUTION_ID = fdh.DISTRIBUTION_ID
                            AND fad.TRANSACTION_HEADER_ID = fth.TRANSACTION_HEADER_ID
                            AND fad.SOURCE_TYPE_CODE IN ('ADJUSTMENT', 'CIP ADJUSTMENT')
                            AND fad.ADJUSTMENT_TYPE IN ('COST CLEARING')
                            AND fad.SOURCE_DEST_CODE IS NULL
                            AND fth.TRANSACTION_DATE_ENTERED <= (:P_FROM_DATE))
                            , 0)
        )) Adjustments
        ,SUM(DISTINCT NVL((SELECT SUM(fad.ADJUSTMENT_AMOUNT * DECODE(fad.DEBIT_CREDIT_FLAG, 'DR', -1, 'CR', 1))
                            FROM FA_ADJUSTMENTS fad
                            WHERE fad.ASSET_ID = fab.ASSET_ID
                            AND fad.DISTRIBUTION_ID = fdh.DISTRIBUTION_ID
                            AND fad.TRANSACTION_HEADER_ID = fth.TRANSACTION_HEADER_ID
                            AND fad.SOURCE_TYPE_CODE IN ('RETIREMENT')
                            AND fad.ADJUSTMENT_TYPE IN ('NBV RETIRED')
                            AND fth.TRANSACTION_DATE_ENTERED <= (:P_FROM_DATE))
                            , 0)
        ) Retirements
        ,SUM(DISTINCT (SELECT NVL(SUM(fds2.DEPRN_RESERVE),0)
        FROM FA_DEPRN_SUMMARY fds2
        WHERE fds2.ASSET_ID = fds.ASSET_ID
        AND fds2.DEPRN_SOURCE_CODE = 'DEPRN'
        AND fds2.PERIOD_COUNTER = (SELECT MAX (PERIOD_COUNTER)
                                        FROM FA_DEPRN_SUMMARY fds3
                                        WHERE fds3.ASSET_ID = fds.ASSET_ID
                                        AND   fds3.DEPRN_RUN_DATE <= (:P_FROM_DATE)))
        ) Beginning_Deprn
        ,SUM(DISTINCT (SELECT NVL(SUM(fds2.IMPAIRMENT_RESERVE),0)
        FROM FA_DEPRN_SUMMARY fds2
        WHERE fds2.ASSET_ID = fds.ASSET_ID
        AND fds2.DEPRN_SOURCE_CODE = 'DEPRN'
        AND fds2.PERIOD_COUNTER = (SELECT MAX (PERIOD_COUNTER)
                                        FROM FA_DEPRN_SUMMARY fds3
                                        WHERE fds3.ASSET_ID = fds.ASSET_ID
                                        AND   fds3.DEPRN_RUN_DATE <= (:P_FROM_DATE)))
        ) Beginning_Impair_Deprn

FROM  FA_ADDITIONS_B fab
    LEFT JOIN FA_BOOKS fb ON fab.ASSET_ID = fb.ASSET_ID
    LEFT JOIN FA_DEPRN_SUMMARY fds ON fb.ASSET_ID = fds.ASSET_ID
    LEFT JOIN FA_TRANSACTION_HEADERS fth ON fab.ASSET_ID = fth.ASSET_ID
    LEFT JOIN FA_DISTRIBUTION_HISTORY fdh ON fb.ASSET_ID = fdh.ASSET_ID
    LEFT JOIN GL_CODE_COMBINATIONS gcc ON fdh.CODE_COMBINATION_ID = gcc.CODE_COMBINATION_ID
    LEFT JOIN FND_FLEX_VALUES_VL ffv ON gcc.SEGMENT2 = ffv.FLEX_VALUE
    LEFT JOIN FA_DEPRN_PERIODS fdp ON fdp.PERIOD_COUNTER = fds.PERIOD_COUNTER
    
WHERE fb.DATE_INEFFECTIVE IS NULL
AND fds.DEPRN_SOURCE_CODE = 'DEPRN'
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
         ,fds.DEPRN_RESERVE 
        ,fds.ADJUSTED_COST 
        ,fds.IMPAIRMENT_RESERVE

) 
GROUP BY Asset_Book
        --,Asset_Number
        --,Asset_Type
        --,Transaction_Month
        ,Store_Number
        ,Store_Location
        
ORDER BY Asset_Book
        --,Asset_Type
        --,Asset_Number
        --,Transaction_Month
        ,Store_Number