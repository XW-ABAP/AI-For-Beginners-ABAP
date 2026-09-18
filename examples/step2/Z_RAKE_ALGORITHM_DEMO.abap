*&---------------------------------------------------------------------*
*& Report Z_RAKE_ALGORITHM_DEMO
*& Description: RAKE Algorithm matching Python nlp_rake logic & ALV
*&---------------------------------------------------------------------*
REPORT z_rake_algorithm_demo.

*----------------------------------------------------------------------*
* CLASS lcl_rake_extractor DEFINITION
*----------------------------------------------------------------------*
CLASS lcl_rake_extractor DEFINITION.
  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_keyword,
        phrase TYPE string,
        score  TYPE decfloat16, " 使用十进制浮点数，解决 E+00 显示问题
      END OF ty_keyword,
      tt_keywords TYPE STANDARD TABLE OF ty_keyword WITH EMPTY KEY.

    METHODS constructor
      IMPORTING
        it_stopwords TYPE string_table.

    METHODS extract_keywords
      IMPORTING
        iv_text            TYPE string
        iv_top_n           TYPE i DEFAULT 20
        iv_max_words       TYPE i DEFAULT 2  " 对应 Python: max_words=2
        iv_min_freq        TYPE i DEFAULT 3  " 对应 Python: min_freq=3
        iv_min_chars       TYPE i DEFAULT 5  " 对应 Python: min_chars=5
      RETURNING
        VALUE(rt_keywords) TYPE tt_keywords.

  PRIVATE SECTION.
    DATA mt_stopwords TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.

    METHODS get_candidate_phrases
      IMPORTING iv_text           TYPE string
      RETURNING VALUE(rt_phrases) TYPE string_table.
ENDCLASS.

CLASS lcl_rake_extractor IMPLEMENTATION.
  METHOD constructor.
    LOOP AT it_stopwords INTO DATA(lv_stopword).
      DATA(lv_lower) = to_lower( lv_stopword ).
      INSERT lv_lower INTO TABLE mt_stopwords.
    ENDLOOP.
  ENDMETHOD.

  METHOD get_candidate_phrases.
    DATA(lv_text) = to_lower( iv_text ).
    REPLACE ALL OCCURRENCES OF REGEX `[.,\/#!$%\^&\*;:{}=\-_~()?"'\[\]]` IN lv_text WITH `|`.
    REPLACE ALL OCCURRENCES OF REGEX `\s+` IN lv_text WITH ` `.

    SPLIT lv_text AT `|` INTO TABLE DATA(lt_chunks).

    LOOP AT lt_chunks INTO DATA(lv_chunk).
      CONDENSE lv_chunk.
      CHECK lv_chunk IS NOT INITIAL.

      SPLIT lv_chunk AT ` ` INTO TABLE DATA(lt_words).
      DATA(lv_current_phrase) = ``.

      LOOP AT lt_words INTO DATA(lv_word).
        IF line_exists( mt_stopwords[ table_line = lv_word ] ).
          IF lv_current_phrase IS NOT INITIAL.
            CONDENSE lv_current_phrase.
            APPEND lv_current_phrase TO rt_phrases.
            lv_current_phrase = ``.
          ENDIF.
        ELSE.
          IF lv_current_phrase IS INITIAL.
            lv_current_phrase = lv_word.
          ELSE.
            lv_current_phrase = lv_current_phrase && ` ` && lv_word.
          ENDIF.
        ENDIF.
      ENDLOOP.

      IF lv_current_phrase IS NOT INITIAL.
        CONDENSE lv_current_phrase.
        APPEND lv_current_phrase TO rt_phrases.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD extract_keywords.
    TYPES: BEGIN OF ty_word_stat,
             word  TYPE string,
             freq  TYPE i,
             deg   TYPE i,
             score TYPE decfloat16,
           END OF ty_word_stat,
           tt_word_stats TYPE HASHED TABLE OF ty_word_stat WITH UNIQUE KEY word.

    DATA lt_word_stats TYPE tt_word_stats.
    DATA lt_scored_phrases TYPE STANDARD TABLE OF ty_keyword.

    " 1. 获取候选短语
    DATA(lt_phrases) = get_candidate_phrases( iv_text ).

    " 2. 统计单词的 Freq 和 Degree (基于所有候选短语)
    LOOP AT lt_phrases INTO DATA(lv_phrase).
      SPLIT lv_phrase AT ` ` INTO TABLE DATA(lt_phrase_words).
      DATA(lv_phrase_len) = lines( lt_phrase_words ).

      LOOP AT lt_phrase_words INTO DATA(lv_word).
        ASSIGN lt_word_stats[ word = lv_word ] TO FIELD-SYMBOL(<fs_stat>).
        IF sy-subrc <> 0.
          INSERT VALUE #( word = lv_word freq = 1 deg = lv_phrase_len ) INTO TABLE lt_word_stats ASSIGNING <fs_stat>.
        ELSE.
          <fs_stat>-freq = <fs_stat>-freq + 1.
          <fs_stat>-deg  = <fs_stat>-deg  + lv_phrase_len.
        ENDIF.
      ENDLOOP.
    ENDLOOP.

    LOOP AT lt_word_stats ASSIGNING <fs_stat>.
      IF <fs_stat>-freq > 0.
        <fs_stat>-score = CONV decfloat16( <fs_stat>-deg ) / CONV decfloat16( <fs_stat>-freq ).
      ENDIF.
    ENDLOOP.

    " 3. 统计每个短语的出现频率 (用于 min_freq 过滤)
    TYPES: BEGIN OF ty_phrase_freq,
             phrase TYPE string,
             freq   TYPE i,
           END OF ty_phrase_freq.
    DATA lt_phrase_freq TYPE HASHED TABLE OF ty_phrase_freq WITH UNIQUE KEY phrase.

    LOOP AT lt_phrases INTO lv_phrase.
      ASSIGN lt_phrase_freq[ phrase = lv_phrase ] TO FIELD-SYMBOL(<fs_pfreq>).
      IF sy-subrc = 0.
        <fs_pfreq>-freq = <fs_pfreq>-freq + 1.
      ELSE.
        INSERT VALUE #( phrase = lv_phrase freq = 1 ) INTO TABLE lt_phrase_freq.
      ENDIF.
    ENDLOOP.

    " 4. 应用 Python 的 RAKE 过滤参数，并计算最终得分
    LOOP AT lt_phrase_freq INTO DATA(ls_pfreq).

      " 过滤 1: min_freq (最小出现频率)
      IF ls_pfreq-freq < iv_min_freq.
        CONTINUE.
      ENDIF.

      " 过滤 2: min_chars (最小字符长度)
      IF strlen( ls_pfreq-phrase ) < iv_min_chars.
        CONTINUE.
      ENDIF.

      SPLIT ls_pfreq-phrase AT ` ` INTO TABLE lt_phrase_words.

      " 过滤 3: max_words (最大单词数)
      IF lines( lt_phrase_words ) > iv_max_words.
        CONTINUE.
      ENDIF.

      " 通过过滤，计算得分
      DATA(lv_phrase_score) = CONV decfloat16( 0 ).
      LOOP AT lt_phrase_words INTO lv_word.
        READ TABLE lt_word_stats WITH TABLE KEY word = lv_word INTO DATA(ls_stat).
        IF sy-subrc = 0.
          lv_phrase_score = lv_phrase_score + ls_stat-score.
        ENDIF.
      ENDLOOP.

      APPEND VALUE #( phrase = ls_pfreq-phrase score = lv_phrase_score ) TO lt_scored_phrases.
    ENDLOOP.

    " 排序并提取 Top N
    SORT lt_scored_phrases BY score DESCENDING.

    LOOP AT lt_scored_phrases INTO DATA(ls_scored).
      IF sy-tabix > iv_top_n.
        EXIT.
      ENDIF.
      APPEND ls_scored TO rt_keywords.
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.

*----------------------------------------------------------------------*
* UI 定义与全局变量
*----------------------------------------------------------------------*
*DATA: gv_title(50) TYPE c,
*      gv_promp(50) TYPE c.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE gv_title.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) gv_promp FOR FIELD p_topn.
    PARAMETERS: p_topn TYPE i DEFAULT 20.
  SELECTION-SCREEN END OF LINE.

  " 增加与 Python 对齐的算法参数
  PARAMETERS: p_maxw TYPE i DEFAULT 2, " max_words
              p_minf TYPE i DEFAULT 2, " min_freq
              p_minc TYPE i DEFAULT 5. " min_chars
SELECTION-SCREEN END OF BLOCK b1.

DATA: go_container TYPE REF TO cl_gui_docking_container,
      go_editor    TYPE REF TO cl_gui_textedit.

INITIALIZATION.
  gv_title = 'RAKE Algorithm Parameters'.
  gv_promp = 'Get the top N keywords:'.

*----------------------------------------------------------------------*
* 屏幕初始化
*----------------------------------------------------------------------*
AT SELECTION-SCREEN OUTPUT.
  IF go_container IS INITIAL.
    CREATE OBJECT go_container
      EXPORTING
        repid     = sy-repid
        dynnr     = sy-dynnr
        side      = cl_gui_docking_container=>dock_at_bottom
        extension = 300.

    CREATE OBJECT go_editor
      EXPORTING
        parent                     = go_container
        wordwrap_mode              = cl_gui_textedit=>wordwrap_at_windowborder
        wordwrap_to_linebreak_mode = cl_gui_textedit=>true.

    go_editor->set_toolbar_mode( cl_gui_textedit=>false ).
    go_editor->set_statusbar_mode( cl_gui_textedit=>false ).

    DATA(lv_default_text) =
      `Data science is an interdisciplinary academic field that uses statistics, ` &&
      `scientific computing, scientific methods, processes, algorithms and systems ` &&
      `to extract or extrapolate knowledge and insights from noisy, structured, and ` &&
      `unstructured data. Data science also integrates domain knowledge from the ` &&
      `underlying application domain. Data science is multifaceted and can be ` &&
      `described as a science, a research paradigm, a research method, a ` &&
      `discipline, a workflow, and a profession.`
      && cl_abap_char_utilities=>cr_lf && cl_abap_char_utilities=>cr_lf &&

      `Data science is a concept to unify statistics, data analysis, informatics, ` &&
      `and their related methods in order to understand and analyze actual ` &&
      `phenomena with data. It uses techniques and theories drawn from many fields ` &&
      `within the context of mathematics, statistics, computer science, ` &&
      `information science, and domain knowledge. However, data science is ` &&
      `different from computer science and information science. Turing Award ` &&
      `winner Jim Gray imagined data science as a fourth paradigm of science ` &&
      `(empirical, theoretical, computational, and now data-driven) and asserted ` &&
      `that everything about science is changing because of the impact of ` &&
      `information technology and the data deluge.`
      && cl_abap_char_utilities=>cr_lf && cl_abap_char_utilities=>cr_lf &&

      `A data scientist is someone who creates programming code and combines it ` &&
      `with statistical knowledge to create insights from data. Modern data ` &&
      `science heavily relies on machine learning and big data technologies to ` &&
      `solve complex real-world problems. In the 21st century, data science has ` &&
      `become one of the most critical drivers for business intelligence and ` &&
      `artificial intelligence.`.

    go_editor->set_textstream( text = lv_default_text ).
  ENDIF.

*----------------------------------------------------------------------*
* 程序执行主逻辑
*----------------------------------------------------------------------*
START-OF-SELECTION.
  DATA: lv_input_text TYPE string.

  go_editor->get_textstream( IMPORTING text = lv_input_text ).
  cl_gui_cfw=>flush( ).

  IF lv_input_text IS INITIAL.
    MESSAGE '请输入测试文本！' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  " 标准 RAKE 英文停用词表
  DATA(lt_stopwords) = VALUE string_table(
    ( `a` ) ( `an` ) ( `and` ) ( `are` ) ( `as` ) ( `at` ) ( `be` ) ( `by` ) ( `for` )
    ( `from` ) ( `has` ) ( `he` ) ( `in` ) ( `is` ) ( `it` ) ( `its` ) ( `of` ) ( `on` )
    ( `that` ) ( `the` ) ( `to` ) ( `was` ) ( `were` ) ( `will` ) ( `with` ) ( `over` ) ( `all` )
  ).

  DATA(lo_rake) = NEW lcl_rake_extractor( it_stopwords = lt_stopwords ).

  " 传入 UI 参数
  DATA(lt_results) = lo_rake->extract_keywords(
    iv_text      = lv_input_text
    iv_top_n     = p_topn
    iv_max_words = p_maxw
    iv_min_freq  = p_minf
    iv_min_chars = p_minc
  ).

  " 使用标准 ALV 显示结果 (完美还原 Python 的列表输出格式)
  DATA: lo_alv TYPE REF TO cl_salv_table.
  TRY.
      cl_salv_table=>factory(
        IMPORTING
          r_salv_table = lo_alv
        CHANGING
          t_table      = lt_results ).

      DATA(lo_columns) = lo_alv->get_columns( ).
      lo_columns->set_optimize( abap_true ).

      " 调整列名以匹配 Python 输出语义
      DATA(lo_column) = lo_columns->get_column( 'PHRASE' ).
      lo_column->set_short_text( 'Keyword' ).
      lo_column->set_medium_text( 'Extracted Keyword' ).

      lo_column = lo_columns->get_column( 'SCORE' ).
      lo_column->set_short_text( 'Score' ).
      lo_column->set_medium_text( 'Relevance Score' ).

      lo_alv->display( ).

    CATCH cx_salv_msg cx_salv_not_found.
      MESSAGE 'ALV 显示失败' TYPE 'E'.
  ENDTRY.
