WITH MAIN AS 
(SELECT  Major_Asset_Category
        ,Minor_Asset_Category
        ,Store_Location
        ,Additions + Adjustments + Retirements Cost
FROM (SELECT  fb.BOOK_TYPE_CODE Asset_Book
        ,fab.ASSET_NUMBER Asset_Number
        ,fab.ASSET_TYPE Asset_Type
        ,TO_CHAR(fth.TRANSACTION_DATE_ENTERED, 'MM/DD/YYYY') Transaction_Date
        ,fcb.SEGMENT1 Major_Asset_Category
        ,fcb.SEGMENT2 Minor_Asset_Category
        ,ffv.DESCRIPTION Store_Location
        ,SUM(DISTINCT NVL((SELECT SUM(fad.ADJUSTMENT_AMOUNT)
                            FROM FA_ADJUSTMENTS fad
                            WHERE fad.ASSET_ID = fab.ASSET_ID
                            AND fad.DISTRIBUTION_ID = fdh.DISTRIBUTION_ID
                            AND fad.TRANSACTION_HEADER_ID = fth.TRANSACTION_HEADER_ID
                            AND fad.SOURCE_TYPE_CODE IN ('ADDITION', 'CIP ADDITION')
                            AND fad.DEBIT_CREDIT_FLAG = 'CR')
                            , 0)
        ) Additions
        ,(SUM(DISTINCT NVL((SELECT SUM(fad.ADJUSTMENT_AMOUNT * DECODE(fad.SOURCE_DEST_CODE, 'DEST', 1, 'SOURCE', -1))
                            FROM FA_ADJUSTMENTS fad
                            WHERE fad.ASSET_ID = fab.ASSET_ID
                            AND fad.DISTRIBUTION_ID = fdh.DISTRIBUTION_ID
                            AND fad.TRANSACTION_HEADER_ID = fth.TRANSACTION_HEADER_ID
                            AND fad.SOURCE_TYPE_CODE IN ('ADJUSTMENT', 'CIP ADJUSTMENT')
                            AND fad.ADJUSTMENT_TYPE IN ('COST', 'CIP COST')
                            AND fad.SOURCE_DEST_CODE IS NOT NULL)
                            , 0)
            ) + SUM(DISTINCT NVL((SELECT SUM(fad.ADJUSTMENT_AMOUNT * DECODE(fad.DEBIT_CREDIT_FLAG, 'DR', -1, 'CR', 1))
                            FROM FA_ADJUSTMENTS fad
                            WHERE fad.ASSET_ID = fab.ASSET_ID
                            AND fad.DISTRIBUTION_ID = fdh.DISTRIBUTION_ID
                            AND fad.TRANSACTION_HEADER_ID = fth.TRANSACTION_HEADER_ID
                            AND fad.SOURCE_TYPE_CODE IN ('ADJUSTMENT', 'CIP ADJUSTMENT')
                            AND fad.ADJUSTMENT_TYPE IN ('COST CLEARING')
                            AND fad.SOURCE_DEST_CODE IS NULL)
                            , 0)
        )) Adjustments
        ,SUM(DISTINCT NVL((SELECT SUM(fad.ADJUSTMENT_AMOUNT * DECODE(fad.DEBIT_CREDIT_FLAG, 'DR', -1, 'CR', 1))
                            FROM FA_ADJUSTMENTS fad
                            WHERE fad.ASSET_ID = fab.ASSET_ID
                            AND fad.DISTRIBUTION_ID = fdh.DISTRIBUTION_ID
                            AND fad.TRANSACTION_HEADER_ID = fth.TRANSACTION_HEADER_ID
                            AND fad.SOURCE_TYPE_CODE IN ('RETIREMENT')
                            AND fad.ADJUSTMENT_TYPE IN ('NBV RETIRED'))
                            , 0)
        ) Retirements
FROM  FA_ADDITIONS_B fab
    LEFT JOIN FA_BOOKS fb ON fab.ASSET_ID = fb.ASSET_ID
    LEFT JOIN FA_TRANSACTION_HEADERS fth ON fab.ASSET_ID = fth.ASSET_ID
    LEFT JOIN FA_CATEGORIES_B fcb ON fab.ASSET_CATEGORY_ID = fcb.CATEGORY_ID
    LEFT JOIN FA_DISTRIBUTION_HISTORY fdh ON fab.ASSET_ID = fdh.ASSET_ID
    LEFT JOIN GL_CODE_COMBINATIONS gcc ON fdh.CODE_COMBINATION_ID = gcc.CODE_COMBINATION_ID
    LEFT JOIN FND_FLEX_VALUES_VL ffv ON gcc.SEGMENT2 = ffv.FLEX_VALUE
WHERE fb.DATE_INEFFECTIVE IS NULL
--AND fdh.DATE_INEFFECTIVE IS NULL   
AND ffv.VALUE_CATEGORY = 'Location COA'
AND (:P_Asset_Book IS NULL OR fb.BOOK_TYPE_CODE = :P_Asset_Book)
AND fcb.SEGMENT1 IN (:P_Major_Category)
AND fcb.SEGMENT2 IN (:P_Minor_Category)
AND ffv.FLEX_VALUE IN (:P_Location) 
AND fth.TRANSACTION_DATE_ENTERED BETWEEN (:P_FROM_DATE) AND (:P_TO_DATE)
AND (:P_Asset_Type IS NULL OR fab.ASSET_TYPE = :P_Asset_Type)

GROUP BY fb.BOOK_TYPE_CODE
         ,fab.ASSET_NUMBER
         ,fab.ASSET_TYPE 
         ,fth.TRANSACTION_DATE_ENTERED
         ,fcb.SEGMENT1
         ,fcb.SEGMENT2
         ,ffv.DESCRIPTION
) 
GROUP BY Major_Asset_Category
        ,Minor_Asset_Category
        ,Store_Location
        ,Additions + Adjustments + Retirements
ORDER BY Major_Asset_Category
        ,Minor_Asset_Category
        ,Store_Location)

SELECT  Major_Asset_Category
        ,Minor_Asset_Category
        ,Store_Location
        ,SUM(Cost) Total_Cost
FROM MAIN
GROUP BY Major_Asset_Category
        ,Minor_Asset_Category
        ,Store_Location
ORDER BY Major_Asset_Category
        ,Minor_Asset_Category
        ,Store_Location