col charcode for a3
col name for a30
Select
    To_number(Extractvalue(Column_value,'*/NumCode/text()')) As NumCode,
    Extractvalue(Column_value,'*/CharCode/text()') As Charcode,
    to_number(extractvalue(Column_value,'*/Scale/text()')) as Scale,
    Extractvalue(Column_value,'*/Name/text()') As Name,
    to_number(extractvalue(Column_value,'*/Rate/text()')) as Rate
  FROM TABLE
          (XMLSEQUENCE
              (Httpuritype
                 ('http://www.nbrb.by/Services/XmlExRates.aspx?ondate='|| TO_CHAR(SYSDATE+1,'MM/DD/YYYY')).getxml().extract('/DailyExRates/Currency')
              )
          )
  order by 1
;
