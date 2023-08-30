SELECT  fabuv.BU_NAME Business_Unit,
        ipmtl.PAYMENT_METHOD_NAME Method_of_Payment, 
        attl.DESCRIPTION Payment_Terms, 
        pay_grp_lookup.MEANING Pay_Group, 
        ps.SEGMENT1 Supplier_Number, 
        hp.PARTY_NAME Supplier_Name, 
        ps.VENDOR_TYPE_LOOKUP_CODE Supplier_Type, 
        LTRIM(NVL(hps.PARTY_SITE_NAME, '') || NVL(hp.ADDRESS1, '') || ' ' || NVL(hp.ADDRESS2, '') || ' ' || NVL(hp.ADDRESS3, '') || ' ' || NVL(hp.ADDRESS4, '') || ' ' || NVL(hp.CITY, '')  || ' ' || NVL(hp.STATE, '') || ' ' || NVL(hp.POSTAL_CODE, '') || ' ' || NVL(hp.COUNTRY, ''), ' ') Address, 
        CASE WHEN hp_contact.PERSON_LAST_NAME IS NULL THEN '' ELSE hp_contact.PERSON_LAST_NAME || ', ' END || NVL(hp_contact.PERSON_FIRST_NAME, '') Contact_Name, 
        hp_contact.PRIMARY_PHONE_AREA_CODE || ' ' || hp_contact.PRIMARY_PHONE_NUMBER || ' ' || hp_contact.PRIMARY_PHONE_EXTENSION Phone,
        hp_contact.EMAIL_ADDRESS Email, 
        ps.TYPE_1099 Federal_Income_Tax_Type, 
        psp.INCOME_TAX_ID Taxpayer_ID, 
        TO_CHAR(ps.CREATION_DATE, 'MM/DD/YYYY') Creation_Date,
        hp_parent.PARTY_NAME Parent_Supplier,
        psv.VENDOR_NAME_ALT Alternate_Name,
        CASE WHEN psav.ADDRESS_PURPOSE_ORDERING = 'Y' THEN 'Ordering ' ELSE '' END
        ||CASE WHEN psav.ADDRESS_PURPOSE_REMIT_TO = 'Y' THEN 'Remit to ' ELSE '' END
        ||CASE WHEN psav.ADDRESS_PURPOSE_RFQ_OR_BIDDING = 'Y' THEN 'RFQ or Bidding ' ELSE '' END AS Address_Purpose,
        COUNT(DISTINCT aia.INVOICE_ID) Total_Invoice_Count,
        SUM (NVL(aia.INVOICE_AMOUNT, 0)) Total_Invoice_Amount,
        COUNT (DISTINCT ipa.PAYMENT_ID) No_Of_Payments,
        COUNT(DISTINCT pha.segment1) Total_PO_Count

        FROM    FUN_ALL_BUSINESS_UNITS_V fabuv, 
                AP_INVOICES_ALL aia, 
                IBY_PAYMENT_METHODS_TL ipmtl, 
                AP_TERMS_TL attl, 
                FND_LOOKUP_VALUES pay_grp_lookup, 
                POZ_SUPPLIERS ps, 
                HZ_PARTIES hp, 
                HZ_PARTIES hp_contact,
                HZ_PARTIES hp_parent,
                HZ_PARTY_SITES hps,
                POZ_SUPPLIERS ps_parent,
                POZ_SUPPLIERS_PII psp,
                POZ_SUPPLIERS_V psv,
                POZ_SUPPLIER_ADDRESS_V psav,
                AP_INVOICE_DISTRIBUTIONS_ALL aida,
                IBY_PAYMENTS_ALL ipa,
                AP_CHECKS_ALL aca,
                PO_HEADERS_ALL pha,
                PO_DISTRIBUTIONS_ALL pda

        WHERE   hp.PARTY_ID = ps.PARTY_ID
        AND     aia.VENDOR_ID = ps.VENDOR_ID
        AND     fabuv.BU_ID = aia.ORG_ID
        AND     ipmtl.PAYMENT_METHOD_CODE (+) = aia.PAYMENT_METHOD_CODE
        AND     attl.TERM_ID (+) = aia.TERMS_ID
        AND     pay_grp_lookup.LOOKUP_TYPE (+) = 'PAY GROUP'
        AND     pay_grp_lookup.LOOKUP_CODE (+) = aia.PAY_GROUP_LOOKUP_CODE
        AND     hps.PARTY_SITE_ID (+) = hp.IDEN_ADDR_PARTY_SITE_ID
        AND     hp_contact.PARTY_ID (+) = hp.PREFERRED_CONTACT_PERSON_ID
        AND     psp.VENDOR_ID (+) = ps.VENDOR_ID
        AND     ps_parent.PARTY_ID (+) = ps.PARENT_PARTY_ID
        AND     hp_parent.PARTY_ID (+) = ps_parent.PARTY_ID
        AND     psv.VENDOR_ID (+) = ps.VENDOR_ID
        AND     psav.VENDOR_ID (+) = ps.VENDOR_ID
        AND     psav.PARTY_ID (+) = hp.PARTY_ID
        AND     aida.INVOICE_ID = aia.INVOICE_ID
        AND     aca.VENDOR_ID = ps.VENDOR_ID
        AND     aca.PARTY_ID = hp.PARTY_ID
        AND     ipa.PAYMENT_ID = aca.PAYMENT_ID
        AND     pda.PO_DISTRIBUTION_ID (+) = aida.PO_DISTRIBUTION_ID
        AND     pha.PO_HEADER_ID (+) = pda.PO_HEADER_ID
        AND     pha.VENDOR_ID (+) = ps.VENDOR_ID
        AND     aida.ACCOUNTING_DATE BETWEEN (:From_Invoice_Accounting_Date) AND (:To_Invoice_Accounting_Date)
        AND     :From_Invoice_Accounting_Date <= :To_Invoice_Accounting_Date
        AND     ipa.PAYMENT_DATE >= :From_Invoice_Accounting_Date
        AND     ipa.PAYMENT_DATE <= :To_Invoice_Accounting_Date
        AND     hp.STATUS = NVL(:Supplier_Status, hp.STATUS)
        AND     fabuv.BU_ID = NVL(:Business_Unit, fabuv.BU_ID)
        GROUP BY ps.SEGMENT1,
                 ps.VENDOR_ID,
                 fabuv.BU_NAME, ipmtl.PAYMENT_METHOD_NAME, 
                 attl.DESCRIPTION, 
                 pay_grp_lookup.MEANING, 
                 hp.PARTY_NAME, ps.VENDOR_TYPE_LOOKUP_CODE, 
                 LTRIM(NVL(hps.PARTY_SITE_NAME, '') || NVL(hp.ADDRESS1, '') || ' ' || NVL(hp.ADDRESS2, '') || ' ' || NVL(hp.ADDRESS3, '') || ' ' || NVL(hp.ADDRESS4, '') || ' ' || NVL(hp.CITY, '') || ' ' || NVL(hp.STATE, '') || ' ' || NVL(hp.POSTAL_CODE, '') || ' ' || NVL(hp.COUNTRY, ''), ' '), 
                 CASE WHEN hp_contact.PERSON_LAST_NAME IS NULL THEN '' ELSE hp_contact.PERSON_LAST_NAME || ', ' END || NVL(hp_contact.PERSON_FIRST_NAME, ''), 
                 hp_contact.PRIMARY_PHONE_AREA_CODE || ' ' || hp_contact.PRIMARY_PHONE_NUMBER || ' ' || hp_contact.PRIMARY_PHONE_EXTENSION,
                 hp_contact.EMAIL_ADDRESS, 
                 ps.TYPE_1099, 
                 psp.INCOME_TAX_ID, 
                 TO_CHAR(ps.CREATION_DATE, 'MM/DD/YYYY'), 
                 hp_parent.PARTY_NAME, 
                 psv.VENDOR_NAME_ALT, 
                 CASE WHEN psav.ADDRESS_PURPOSE_ORDERING = 'Y' THEN 'Ordering ' ELSE '' END 
                 ||CASE WHEN psav.ADDRESS_PURPOSE_REMIT_TO = 'Y' THEN 'Remit to ' ELSE '' END 
                 ||CASE WHEN psav.ADDRESS_PURPOSE_RFQ_OR_BIDDING = 'Y' THEN 'RFQ or Bidding ' ELSE '' END
        ORDER BY ps.SEGMENT1 ASC