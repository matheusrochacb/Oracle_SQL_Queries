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
), CIP_LISTING_IN_RANGE AS (
        SELECT  ppav.PROJECT_ID                 AS Project_id,
                ppav.NAME                       AS Project_Name,
                ppav.SEGMENT1                   AS Project_Number,
                ppet.name                       AS Task_Name,
                ppe.ELEMENT_NUMBER              AS Task_Number,
                ppe.PROJ_ELEMENT_ID             AS Task_id,
                peia.EXPENDITURE_ITEM_DATE      AS Expenditure_Item_Date,
                ROUND(pcdla.PROJFUNC_RAW_COST,2) AS Cost,
                ppn.Display_Name                AS Employee,
                peia.EXPENDITURE_ITEM_ID        AS Transaction_Number,
                hp.PARTY_NAME                   AS Supplier,
                ppav.ATTRIBUTE1                 AS Legal_Entity,
                peia.CAPITALIZATION_DIST_FLAG   AS CIP_Flag,
                pcdla.PRVDR_GL_PERIOD_NAME      AS GL_Period,
                CASE WHEN pcct.CLASS_CODE != 'Task Level' THEN pcct.CLASS_CODE ELSE flv.MEANING END AS Location,
                NVL((SELECT DISTINCT gcc.SEGMENT1 || '-' || gcc.SEGMENT2 || '-' || gcc.SEGMENT3 || '-' || 
                                gcc.SEGMENT4 || '-' || gcc.SEGMENT5 || '-' || gcc.SEGMENT6 || '-' || 
                                gcc.SEGMENT7 
                FROM    GL_CODE_COMBINATIONS gcc,
                        XLA_AE_HEADERS xah,
                        XLA_AE_LINES xal
                WHERE   1=1
                AND     pcdla.ACCT_EVENT_ID = xah.EVENT_ID
                AND     xah.AE_HEADER_ID = xal.AE_HEADER_ID
                AND     xal.CODE_COMBINATION_ID = gcc.CODE_COMBINATION_ID
                AND     xal.ACCOUNTED_DR IS NOT NULL
                AND     xal.OVERRIDE_REASON IS NULL
                AND     ROWNUM=1), 
                NVL((SELECT  DISTINCT gcc.SEGMENT1 || '-' || gcc.SEGMENT2 || '-' || gcc.SEGMENT3 || '-' || 
                gcc.SEGMENT4 || '-' || gcc.SEGMENT5 || '-' || gcc.SEGMENT6 || '-' || 
                gcc.SEGMENT7 
                FROM    GL_CODE_COMBINATIONS gcc,
                        AP_INVOICE_DISTRIBUTIONS_ALL aida,
                        XLA_AE_HEADERS xah,
                        XLA_AE_LINES xal
                WHERE   1=1
                AND     peia.ORIGINAL_HEADER_ID = aida.INVOICE_ID(+)
                AND     aida.ACCOUNTING_EVENT_ID = xah.EVENT_ID
                AND     xah.AE_HEADER_ID = xal.AE_HEADER_ID
                AND     xal.CODE_COMBINATION_ID = gcc.CODE_COMBINATION_ID
                AND     xal.ACCOUNTED_DR IS NOT NULL
                AND     xal.OVERRIDE_REASON IS NULL
                AND     ROWNUM=1),
                NVL((SELECT gcc.SEGMENT1 || '-' || gcc.SEGMENT2 || '-' || gcc.SEGMENT3 || '-' || 
                        gcc.SEGMENT4 || '-' || gcc.SEGMENT5 || '-' || gcc.SEGMENT6 || '-' || 
                        gcc.SEGMENT7
                FROM    GL_CODE_COMBINATIONS gcc
                WHERE   pcdla.RAW_COST_DR_CCID = gcc.CODE_COMBINATION_ID
                AND     pcdla.ACCOUNTING_STATUS_CODE != 'RNBNN'),NULL))
                ) AS Raw_Cost_Debit_Acct,
                (SELECT flv1.MEANING 
                FROM    FND_LOOKUP_VALUES flv1,
                        PJC_PRJ_ASSET_LNS_ALL ala,
                        PJC_PRJ_ASSET_LN_DETS ald
                WHERE   flv1.LOOKUP_TYPE(+) = 'PJC_TRANSFER_STATUS'
                AND     flv1.LOOKUP_CODE(+) = ala.TRANSFER_STATUS_CODE
                --AND     ala.project_id = ppav.project_id
                AND     ald.EXPENDITURE_ITEM_ID = peia.EXPENDITURE_ITEM_ID
                AND     ala.PROJECT_ASSET_LINE_DETAIL_ID = ald.PROJECT_ASSET_LINE_DETAIL_ID
                --AND     NVL(ala.ORIGINAL_ASSET_COST,0) != 0
                --AND     ala.INVOICE_DISTRIBUTION_ID = peia.ORIG_TRANSACTION_REFERENCE
                AND     ROWNUM=1
                ) AS Asset_Status,
                pcdla.PRVDR_GL_DATE Provider_acc_date
        FROM    PJF_PROJECTS_ALL_VL ppav,
                PJF_PROJ_ELEMENTS_B ppe,
                PJF_PROJ_ELEMENTS_TL ppet,
                PJC_COST_DIST_LINES_ALL pcdla,
                PJC_EXP_ITEMS_ALL peia,
                per_person_names_f_v ppn,
                AP_INVOICES_ALL aia,
                POZ_SUPPLIERS ps,
                HZ_PARTIES hp,
                FND_LOOKUP_VALUES flv,
                PJF_CLASS_CODES_B pcc,
                PJF_CLASS_CODES_TL pcct,
                PJF_PROJECT_CLASSES ppc,
                date_params dp
        WHERE   1=1 
        AND     ppav.PROJECT_ID = pcdla.Project_id
        AND     pcdla.EXPENDITURE_ITEM_ID = peia.EXPENDITURE_ITEM_ID
        AND     ppe.PROJECT_ID = pcdla.Project_id
        AND     ppe.PROJ_ELEMENT_ID = pcdla.TASK_ID
        AND     ppe.PROJ_ELEMENT_ID = ppet.PROJ_ELEMENT_ID
        AND     ppn.person_id(+) = peia.INCURRED_BY_PERSON_ID
        AND     peia.ORIGINAL_HEADER_ID = aia.INVOICE_ID(+)
        AND     aia.VENDOR_ID = ps.VENDOR_ID(+)
        AND     hp.PARTY_ID(+) = ps.PARTY_ID
        AND     flv.LOOKUP_TYPE(+) = 'PJF_SERVICE_TYPE'
        AND     flv.LOOKUP_CODE(+) = ppe.SERVICE_TYPE_CODE
        AND     ppav.PROJECT_ID = ppc.PROJECT_ID
        AND     ppc.CLASS_CODE_ID = pcc.CLASS_CODE_ID
        AND     pcc.CLASS_CODE_ID = pcct.CLASS_CODE_ID
        AND     pcdla.PRVDR_GL_DATE >= dp.Start_Date
        AND     pcdla.PRVDR_GL_DATE <= dp.End_Date
        AND     (:P_Company IS NULL OR ppav.ATTRIBUTE1 = :P_Company)
), CIP_QUERY_IN_RANGE AS (
        SELECT  SUM(CASE WHEN clist1.Provider_acc_date >= dp.Q1_Start_Date AND clist1.Provider_acc_date < dp.Q2_Start_Date THEN clist1.Cost ELSE 0 END) Q1_CIP,
                SUM(CASE WHEN clist1.Provider_acc_date >= dp.Q2_Start_Date AND clist1.Provider_acc_date < dp.Q3_Start_Date THEN clist1.Cost ELSE 0 END) Q2_CIP,
                SUM(CASE WHEN clist1.Provider_acc_date >= dp.Q3_Start_Date AND clist1.Provider_acc_date < dp.Q4_Start_Date THEN clist1.Cost ELSE 0 END) Q3_CIP,
                SUM(CASE WHEN clist1.Provider_acc_date >= dp.Q4_Start_Date AND clist1.Provider_acc_date < dp.End_Date THEN clist1.Cost ELSE 0 END) Q4_CIP,
                0 Q1_CIP_CAP,
                0 Q2_CIP_CAP,
                0 Q3_CIP_CAP,
                0 Q4_CIP_CAP
        FROM CIP_LISTING_IN_RANGE clist1
        JOIN date_params dp ON 1=1
        WHERE (clist1.Asset_Status IS NULL OR clist1.Asset_Status = 'Pending')
        UNION ALL
        SELECT  0 Q1_CIP,
                0 Q2_CIP,
                0 Q3_CIP,
                0 Q4_CIP,
                SUM(CASE WHEN clist2.Provider_acc_date >= dp.Q1_Start_Date AND clist2.Provider_acc_date < dp.Q2_Start_Date THEN clist2.Cost ELSE 0 END) Q1_CIP_CAP,
                SUM(CASE WHEN clist2.Provider_acc_date >= dp.Q2_Start_Date AND clist2.Provider_acc_date < dp.Q3_Start_Date THEN clist2.Cost ELSE 0 END) Q2_CIP_CAP,
                SUM(CASE WHEN clist2.Provider_acc_date >= dp.Q3_Start_Date AND clist2.Provider_acc_date < dp.Q4_Start_Date THEN clist2.Cost ELSE 0 END) Q3_CIP_CAP,
                SUM(CASE WHEN clist2.Provider_acc_date >= dp.Q4_Start_Date AND clist2.Provider_acc_date < dp.End_Date THEN clist2.Cost ELSE 0 END) Q4_CIP_CAP
        FROM CIP_LISTING_IN_RANGE clist2
        JOIN date_params dp ON 1=1
        WHERE clist2.Asset_Status = 'Transferred'
), CIP_LISTING_BEG_BAL AS (
        SELECT  ppav.PROJECT_ID                 AS Project_id,
                ppav.NAME                       AS Project_Name,
                ppav.SEGMENT1                   AS Project_Number,
                ppet.name                       AS Task_Name,
                ppe.ELEMENT_NUMBER              AS Task_Number,
                ppe.PROJ_ELEMENT_ID             AS Task_id,
                peia.EXPENDITURE_ITEM_DATE      AS Expenditure_Item_Date,
                ROUND(pcdla.PROJFUNC_RAW_COST,2) AS Cost,
                ppn.Display_Name                AS Employee,
                peia.EXPENDITURE_ITEM_ID        AS Transaction_Number,
                hp.PARTY_NAME                   AS Supplier,
                ppav.ATTRIBUTE1                 AS Legal_Entity,
                peia.CAPITALIZATION_DIST_FLAG   AS CIP_Flag,
                pcdla.PRVDR_GL_PERIOD_NAME      AS GL_Period,
                CASE WHEN pcct.CLASS_CODE != 'Task Level' THEN pcct.CLASS_CODE ELSE flv.MEANING END AS Location,
                NVL((SELECT DISTINCT gcc.SEGMENT1 || '-' || gcc.SEGMENT2 || '-' || gcc.SEGMENT3 || '-' || 
                                gcc.SEGMENT4 || '-' || gcc.SEGMENT5 || '-' || gcc.SEGMENT6 || '-' || 
                                gcc.SEGMENT7 
                FROM    GL_CODE_COMBINATIONS gcc,
                        XLA_AE_HEADERS xah,
                        XLA_AE_LINES xal
                WHERE   1=1
                AND     pcdla.ACCT_EVENT_ID = xah.EVENT_ID
                AND     xah.AE_HEADER_ID = xal.AE_HEADER_ID
                AND     xal.CODE_COMBINATION_ID = gcc.CODE_COMBINATION_ID
                AND     xal.ACCOUNTED_DR IS NOT NULL
                AND     xal.OVERRIDE_REASON IS NULL
                AND     ROWNUM=1), 
                NVL((SELECT  DISTINCT gcc.SEGMENT1 || '-' || gcc.SEGMENT2 || '-' || gcc.SEGMENT3 || '-' || 
                gcc.SEGMENT4 || '-' || gcc.SEGMENT5 || '-' || gcc.SEGMENT6 || '-' || 
                gcc.SEGMENT7 
                FROM    GL_CODE_COMBINATIONS gcc,
                        AP_INVOICE_DISTRIBUTIONS_ALL aida,
                        XLA_AE_HEADERS xah,
                        XLA_AE_LINES xal
                WHERE   1=1
                AND     peia.ORIGINAL_HEADER_ID = aida.INVOICE_ID(+)
                AND     aida.ACCOUNTING_EVENT_ID = xah.EVENT_ID
                AND     xah.AE_HEADER_ID = xal.AE_HEADER_ID
                AND     xal.CODE_COMBINATION_ID = gcc.CODE_COMBINATION_ID
                AND     xal.ACCOUNTED_DR IS NOT NULL
                AND     xal.OVERRIDE_REASON IS NULL
                AND     ROWNUM=1),
                NVL((SELECT gcc.SEGMENT1 || '-' || gcc.SEGMENT2 || '-' || gcc.SEGMENT3 || '-' || 
                        gcc.SEGMENT4 || '-' || gcc.SEGMENT5 || '-' || gcc.SEGMENT6 || '-' || 
                        gcc.SEGMENT7
                FROM    GL_CODE_COMBINATIONS gcc
                WHERE   pcdla.RAW_COST_DR_CCID = gcc.CODE_COMBINATION_ID
                AND     pcdla.ACCOUNTING_STATUS_CODE != 'RNBNN'),NULL))
                ) AS Raw_Cost_Debit_Acct,
                (SELECT flv1.MEANING 
                FROM    FND_LOOKUP_VALUES flv1,
                        PJC_PRJ_ASSET_LNS_ALL ala,
                        PJC_PRJ_ASSET_LN_DETS ald
                WHERE   flv1.LOOKUP_TYPE(+) = 'PJC_TRANSFER_STATUS'
                AND     flv1.LOOKUP_CODE(+) = ala.TRANSFER_STATUS_CODE
                --AND     ala.project_id = ppav.project_id
                AND     ald.EXPENDITURE_ITEM_ID = peia.EXPENDITURE_ITEM_ID
                AND     ala.PROJECT_ASSET_LINE_DETAIL_ID = ald.PROJECT_ASSET_LINE_DETAIL_ID
                --AND     NVL(ala.ORIGINAL_ASSET_COST,0) != 0
                --AND     ala.INVOICE_DISTRIBUTION_ID = peia.ORIG_TRANSACTION_REFERENCE
                AND     ROWNUM=1
                ) AS Asset_Status,
                pcdla.PRVDR_GL_DATE Provider_acc_date
        FROM    PJF_PROJECTS_ALL_VL ppav,
                PJF_PROJ_ELEMENTS_B ppe,
                PJF_PROJ_ELEMENTS_TL ppet,
                PJC_COST_DIST_LINES_ALL pcdla,
                PJC_EXP_ITEMS_ALL peia,
                per_person_names_f_v ppn,
                AP_INVOICES_ALL aia,
                POZ_SUPPLIERS ps,
                HZ_PARTIES hp,
                FND_LOOKUP_VALUES flv,
                PJF_CLASS_CODES_B pcc,
                PJF_CLASS_CODES_TL pcct,
                PJF_PROJECT_CLASSES ppc,
                date_params dp
        WHERE   1=1 
        AND     ppav.PROJECT_ID = pcdla.Project_id
        AND     pcdla.EXPENDITURE_ITEM_ID = peia.EXPENDITURE_ITEM_ID
        AND     ppe.PROJECT_ID = pcdla.Project_id
        AND     ppe.PROJ_ELEMENT_ID = pcdla.TASK_ID
        AND     ppe.PROJ_ELEMENT_ID = ppet.PROJ_ELEMENT_ID
        AND     ppn.person_id(+) = peia.INCURRED_BY_PERSON_ID
        AND     peia.ORIGINAL_HEADER_ID = aia.INVOICE_ID(+)
        AND     aia.VENDOR_ID = ps.VENDOR_ID(+)
        AND     hp.PARTY_ID(+) = ps.PARTY_ID
        AND     flv.LOOKUP_TYPE(+) = 'PJF_SERVICE_TYPE'
        AND     flv.LOOKUP_CODE(+) = ppe.SERVICE_TYPE_CODE
        AND     ppav.PROJECT_ID = ppc.PROJECT_ID
        AND     ppc.CLASS_CODE_ID = pcc.CLASS_CODE_ID
        AND     pcc.CLASS_CODE_ID = pcct.CLASS_CODE_ID
        AND     pcdla.PRVDR_GL_DATE < dp.Start_Date
        AND     (:P_Company IS NULL OR ppav.ATTRIBUTE1 = :P_Company)

), CIP_LISTING_END_BAL AS (
        SELECT  ppav.PROJECT_ID                 AS Project_id,
                ppav.NAME                       AS Project_Name,
                ppav.SEGMENT1                   AS Project_Number,
                ppet.name                       AS Task_Name,
                ppe.ELEMENT_NUMBER              AS Task_Number,
                ppe.PROJ_ELEMENT_ID             AS Task_id,
                peia.EXPENDITURE_ITEM_DATE      AS Expenditure_Item_Date,
                ROUND(pcdla.PROJFUNC_RAW_COST,2) AS Cost,
                ppn.Display_Name                AS Employee,
                peia.EXPENDITURE_ITEM_ID        AS Transaction_Number,
                hp.PARTY_NAME                   AS Supplier,
                ppav.ATTRIBUTE1                 AS Legal_Entity,
                peia.CAPITALIZATION_DIST_FLAG   AS CIP_Flag,
                pcdla.PRVDR_GL_PERIOD_NAME      AS GL_Period,
                CASE WHEN pcct.CLASS_CODE != 'Task Level' THEN pcct.CLASS_CODE ELSE flv.MEANING END AS Location,
                NVL((SELECT DISTINCT gcc.SEGMENT1 || '-' || gcc.SEGMENT2 || '-' || gcc.SEGMENT3 || '-' || 
                                gcc.SEGMENT4 || '-' || gcc.SEGMENT5 || '-' || gcc.SEGMENT6 || '-' || 
                                gcc.SEGMENT7 
                FROM    GL_CODE_COMBINATIONS gcc,
                        XLA_AE_HEADERS xah,
                        XLA_AE_LINES xal
                WHERE   1=1
                AND     pcdla.ACCT_EVENT_ID = xah.EVENT_ID
                AND     xah.AE_HEADER_ID = xal.AE_HEADER_ID
                AND     xal.CODE_COMBINATION_ID = gcc.CODE_COMBINATION_ID
                AND     xal.ACCOUNTED_DR IS NOT NULL
                AND     xal.OVERRIDE_REASON IS NULL
                AND     ROWNUM=1), 
                NVL((SELECT  DISTINCT gcc.SEGMENT1 || '-' || gcc.SEGMENT2 || '-' || gcc.SEGMENT3 || '-' || 
                gcc.SEGMENT4 || '-' || gcc.SEGMENT5 || '-' || gcc.SEGMENT6 || '-' || 
                gcc.SEGMENT7 
                FROM    GL_CODE_COMBINATIONS gcc,
                        AP_INVOICE_DISTRIBUTIONS_ALL aida,
                        XLA_AE_HEADERS xah,
                        XLA_AE_LINES xal
                WHERE   1=1
                AND     peia.ORIGINAL_HEADER_ID = aida.INVOICE_ID(+)
                AND     aida.ACCOUNTING_EVENT_ID = xah.EVENT_ID
                AND     xah.AE_HEADER_ID = xal.AE_HEADER_ID
                AND     xal.CODE_COMBINATION_ID = gcc.CODE_COMBINATION_ID
                AND     xal.ACCOUNTED_DR IS NOT NULL
                AND     xal.OVERRIDE_REASON IS NULL
                AND     ROWNUM=1),
                NVL((SELECT gcc.SEGMENT1 || '-' || gcc.SEGMENT2 || '-' || gcc.SEGMENT3 || '-' || 
                        gcc.SEGMENT4 || '-' || gcc.SEGMENT5 || '-' || gcc.SEGMENT6 || '-' || 
                        gcc.SEGMENT7
                FROM    GL_CODE_COMBINATIONS gcc
                WHERE   pcdla.RAW_COST_DR_CCID = gcc.CODE_COMBINATION_ID
                AND     pcdla.ACCOUNTING_STATUS_CODE != 'RNBNN'),NULL))
                ) AS Raw_Cost_Debit_Acct,
                (SELECT flv1.MEANING 
                FROM    FND_LOOKUP_VALUES flv1,
                        PJC_PRJ_ASSET_LNS_ALL ala,
                        PJC_PRJ_ASSET_LN_DETS ald
                WHERE   flv1.LOOKUP_TYPE(+) = 'PJC_TRANSFER_STATUS'
                AND     flv1.LOOKUP_CODE(+) = ala.TRANSFER_STATUS_CODE
                --AND     ala.project_id = ppav.project_id
                AND     ald.EXPENDITURE_ITEM_ID = peia.EXPENDITURE_ITEM_ID
                AND     ala.PROJECT_ASSET_LINE_DETAIL_ID = ald.PROJECT_ASSET_LINE_DETAIL_ID
                --AND     NVL(ala.ORIGINAL_ASSET_COST,0) != 0
                --AND     ala.INVOICE_DISTRIBUTION_ID = peia.ORIG_TRANSACTION_REFERENCE
                AND     ROWNUM=1
                ) AS Asset_Status,
                pcdla.PRVDR_GL_DATE Provider_acc_date
        FROM    PJF_PROJECTS_ALL_VL ppav,
                PJF_PROJ_ELEMENTS_B ppe,
                PJF_PROJ_ELEMENTS_TL ppet,
                PJC_COST_DIST_LINES_ALL pcdla,
                PJC_EXP_ITEMS_ALL peia,
                per_person_names_f_v ppn,
                AP_INVOICES_ALL aia,
                POZ_SUPPLIERS ps,
                HZ_PARTIES hp,
                FND_LOOKUP_VALUES flv,
                PJF_CLASS_CODES_B pcc,
                PJF_CLASS_CODES_TL pcct,
                PJF_PROJECT_CLASSES ppc,
                date_params dp
        WHERE   1=1 
        AND     ppav.PROJECT_ID = pcdla.Project_id
        AND     pcdla.EXPENDITURE_ITEM_ID = peia.EXPENDITURE_ITEM_ID
        AND     ppe.PROJECT_ID = pcdla.Project_id
        AND     ppe.PROJ_ELEMENT_ID = pcdla.TASK_ID
        AND     ppe.PROJ_ELEMENT_ID = ppet.PROJ_ELEMENT_ID
        AND     ppn.person_id(+) = peia.INCURRED_BY_PERSON_ID
        AND     peia.ORIGINAL_HEADER_ID = aia.INVOICE_ID(+)
        AND     aia.VENDOR_ID = ps.VENDOR_ID(+)
        AND     hp.PARTY_ID(+) = ps.PARTY_ID
        AND     flv.LOOKUP_TYPE(+) = 'PJF_SERVICE_TYPE'
        AND     flv.LOOKUP_CODE(+) = ppe.SERVICE_TYPE_CODE
        AND     ppav.PROJECT_ID = ppc.PROJECT_ID
        AND     ppc.CLASS_CODE_ID = pcc.CLASS_CODE_ID
        AND     pcc.CLASS_CODE_ID = pcct.CLASS_CODE_ID
        AND     pcdla.PRVDR_GL_DATE < dp.End_Date
        AND     (:P_Company IS NULL OR ppav.ATTRIBUTE1 = :P_Company)

), CIP_QUERY_BEG_END_BAL AS (
        SELECT  NVL(SUM(NVL(clist1.Cost, 0)), 0) Beginning_CIP,
                0 Ending_CIP

        FROM CIP_LISTING_BEG_BAL clist1
        JOIN date_params dp ON 1=1
        WHERE (clist1.Asset_Status IS NULL OR clist1.Asset_Status = 'Pending')
        UNION ALL
        SELECT  0 Beginning_CIP,
                NVL(SUM(NVL(clist2.Cost, 0)), 0) Ending_CIP
                
        FROM CIP_LISTING_END_BAL clist2
        JOIN date_params dp ON 1=1
        WHERE (clist2.Asset_Status IS NULL OR clist2.Asset_Status = 'Pending')
), SUMMARY_QUERY AS (
        SELECT  SUM(NVL(Beginning_CIP, 0)) Beginning_CIP,
                SUM(NVL(Ending_CIP, 0)) Ending_CIP,
                0 Q1_CIP,
                0 Q2_CIP,
                0 Q3_CIP,
                0 Q4_CIP,
                0 Q1_CIP_CAP,
                0 Q2_CIP_CAP,
                0 Q3_CIP_CAP,
                0 Q4_CIP_CAP
        FROM CIP_QUERY_BEG_END_BAL
        UNION ALL
        SELECT  0 Beginning_CIP,
                0 Ending_CIP,
                SUM(NVL(Q1_CIP, 0)) Q1_CIP,
                SUM(NVL(Q2_CIP, 0)) Q2_CIP,
                SUM(NVL(Q3_CIP, 0)) Q3_CIP,
                SUM(NVL(Q4_CIP, 0)) Q4_CIP,
                SUM(NVL(Q1_CIP_CAP, 0)) Q1_CIP_CAP,
                SUM(NVL(Q2_CIP_CAP, 0)) Q2_CIP_CAP,
                SUM(NVL(Q3_CIP_CAP, 0)) Q3_CIP_CAP,
                SUM(NVL(Q4_CIP_CAP, 0)) Q4_CIP_CAP
        FROM    CIP_QUERY_IN_RANGE
)

SELECT  SUM(NVL(Beginning_CIP, 0)) Beginning_CIP,
        SUM(NVL(Ending_CIP, 0)) Ending_CIP,
        SUM(NVL(Q1_CIP, 0)) Q1_CIP,
        SUM(NVL(Q2_CIP, 0)) Q2_CIP,
        SUM(NVL(Q3_CIP, 0)) Q3_CIP,
        SUM(NVL(Q4_CIP, 0)) Q4_CIP,
        SUM(NVL(Q1_CIP_CAP, 0)) * -1 Q1_CIP_CAP,
        SUM(NVL(Q2_CIP_CAP, 0)) * -1 Q2_CIP_CAP,
        SUM(NVL(Q3_CIP_CAP, 0)) * -1 Q3_CIP_CAP,
        SUM(NVL(Q4_CIP_CAP, 0)) * -1 Q4_CIP_CAP
FROM SUMMARY_QUERY
