REPORT z_sentiment_analyzer_en.

*----------------------------------------------------------------------*
* 1. Class Definition
*----------------------------------------------------------------------*
CLASS lcl_sentiment_analyzer DEFINITION.
  PUBLIC SECTION.
    TYPES:
      " Structure of training data
      BEGIN OF ty_training_data,
        text      TYPE string,
        sentiment TYPE string,
      END OF ty_training_data,
      tt_training_data TYPE STANDARD TABLE OF ty_training_data WITH DEFAULT KEY,

      " Structure for word scores (equivalent to a dictionary in Python)
      BEGIN OF ty_word_score,
        word  TYPE string,
        score TYPE decfloat34, " High-precision floating point number
      END OF ty_word_score,
      tt_word_score TYPE HASHED TABLE OF ty_word_score WITH UNIQUE KEY word.

    METHODS:
      train IMPORTING it_data TYPE tt_training_data,
      analyze IMPORTING iv_text      TYPE string
              EXPORTING ev_sentiment TYPE string
                        ev_score     TYPE decfloat34
                        ev_conf      TYPE decfloat34.

  PRIVATE SECTION.
    DATA: mt_word_scores TYPE tt_word_score,
          mv_is_trained  TYPE abap_bool.

    METHODS:
      preprocess_text IMPORTING iv_text         TYPE string
                      RETURNING VALUE(rt_words) TYPE string_table.
ENDCLASS.

*----------------------------------------------------------------------*
* 2. Class Implementation
*----------------------------------------------------------------------*
CLASS lcl_sentiment_analyzer IMPLEMENTATION.

  " Text preprocessing: to lowercase, remove punctuation, and tokenize
  METHOD preprocess_text.
    DATA(lv_text) = to_lower( iv_text ).

    " Regex replacement: keep only lowercase letters and spaces
    REPLACE ALL OCCURRENCES OF REGEX '[^a-z\s]' IN lv_text WITH ''.

    DATA lt_temp_words TYPE string_table.
    SPLIT lv_text AT space INTO TABLE lt_temp_words.

    " Filter out short words with length <= 2 (e.g., 'a', 'is', 'it')
    LOOP AT lt_temp_words INTO DATA(lv_word) WHERE table_line IS NOT INITIAL.
      IF strlen( lv_word ) > 2.
        APPEND lv_word TO rt_words.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  " Train the model: count word frequencies and calculate scores
  METHOD train.
    TYPES: BEGIN OF ty_counter,
             word  TYPE string,
             count TYPE i,
           END OF ty_counter.
    DATA: lt_pos_words TYPE HASHED TABLE OF ty_counter WITH UNIQUE KEY word,
          lt_neg_words TYPE HASHED TABLE OF ty_counter WITH UNIQUE KEY word,
          lt_all_words TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.

    " Step A: Count positive and negative word frequencies
    LOOP AT it_data INTO DATA(ls_data).
      DATA(lt_words) = preprocess_text( ls_data-text ).

      LOOP AT lt_words INTO DATA(lv_word).
        " Record all unique words that appeared
        INSERT lv_word INTO TABLE lt_all_words.

        IF ls_data-sentiment = 'positive'.
          ASSIGN lt_pos_words[ word = lv_word ] TO FIELD-SYMBOL(<fs_pos>).
          IF sy-subrc = 0.
            <fs_pos>-count = <fs_pos>-count + 1.
          ELSE.
            INSERT VALUE #( word = lv_word count = 1 ) INTO TABLE lt_pos_words.
          ENDIF.
        ELSE.
          ASSIGN lt_neg_words[ word = lv_word ] TO FIELD-SYMBOL(<fs_neg>).
          IF sy-subrc = 0.
            <fs_neg>-count = <fs_neg>-count + 1.
          ELSE.
            INSERT VALUE #( word = lv_word count = 1 ) INTO TABLE lt_neg_words.
          ENDIF.
        ENDIF.
      ENDLOOP.
    ENDLOOP.

    " Step B: Calculate the final sentiment score for each word
    LOOP AT lt_all_words INTO DATA(lv_all_word).
      DATA(lv_pos_count) = 0.
      DATA(lv_neg_count) = 0.

      " Safely read the hashed tables
      ASSIGN lt_pos_words[ word = lv_all_word ] TO FIELD-SYMBOL(<fs_p>).
      IF sy-subrc = 0. lv_pos_count = <fs_p>-count. ENDIF.

      ASSIGN lt_neg_words[ word = lv_all_word ] TO FIELD-SYMBOL(<fs_n>).
      IF sy-subrc = 0. lv_neg_count = <fs_n>-count. ENDIF.

      DATA(lv_total) = lv_pos_count + lv_neg_count.

      " Score formula: (positive count - negative count) / (total count + 1 for smoothing)
      DATA(lv_score) = CONV decfloat34( lv_pos_count - lv_neg_count ) / ( lv_total + 1 ).

      INSERT VALUE #( word = lv_all_word score = lv_score ) INTO TABLE mt_word_scores.
    ENDLOOP.

    mv_is_trained = abap_true.
  ENDMETHOD.

  " Analyze new text
  METHOD analyze.
    DATA(lt_words) = preprocess_text( iv_text ).
    DATA(lv_total_score) = CONV decfloat34( 0 ).
    DATA(lv_word_count)  = 0.

    LOOP AT lt_words INTO DATA(lv_word).
      ASSIGN mt_word_scores[ word = lv_word ] TO FIELD-SYMBOL(<fs_score>).
      IF sy-subrc = 0.
        lv_total_score = lv_total_score + <fs_score>-score.
        lv_word_count = lv_word_count + 1.
      ENDIF.
    ENDLOOP.

    " Calculate average score
    IF lv_word_count > 0.
      ev_score = lv_total_score / lv_word_count.
    ELSE.
      ev_score = 0.
    ENDIF.

    " Determine sentiment
    IF ev_score > 0.
      ev_sentiment = 'positive'.
    ELSE.
      ev_sentiment = 'negative'.
    ENDIF.

    " Calculate confidence index (Simulated percentage: between 0 and 100)
    ev_conf = abs( ev_score ) * 100.
    IF ev_conf > 100. ev_conf = 100. ENDIF.
  ENDMETHOD.

ENDCLASS.



SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE gv_title.
  " Enable custom line layout
  SELECTION-SCREEN BEGIN OF LINE.
    " Set prompt text, width 30, and bind it to the input field (FOR FIELD)
    SELECTION-SCREEN COMMENT 1(30) gv_promp FOR FIELD p_input.
    " The input field itself (because a custom line is used, the system's native P_INPUT label will be hidden)
    PARAMETERS: p_input TYPE c LENGTH 200 LOWER CASE OBLIGATORY
                DEFAULT 'This movie was absolutely brilliant and I loved it!'.
  SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK b1.

* Assign title and prompt text in the INITIALIZATION event
INITIALIZATION.
  gv_title  = 'Sentiment Analysis Test'.
  gv_promp = 'Input your review:'.
*----------------------------------------------------------------------*
* 4. Main Program Execution Logic
*----------------------------------------------------------------------*
START-OF-SELECTION.

  " 1. Prepare training data (16 records exactly matching Python)
  DATA lt_training_data TYPE lcl_sentiment_analyzer=>tt_training_data.
  lt_training_data = VALUE #(
    " Positive Reviews (8)
    ( text = `This movie was absolutely amazing and wonderful I loved every minute.` sentiment = `positive` )
    ( text = `Brilliant performance The acting was superb and the story captivating.` sentiment = `positive` )
    ( text = `Fantastic film Highly recommend to everyone Best movie of the year` sentiment = `positive` )
    ( text = `Loved it Great storytelling and beautiful cinematography.` sentiment = `positive` )
    ( text = `Excellent movie with outstanding performances A must watch.` sentiment = `positive` )
    ( text = `Amazing This film exceeded all my expectations Truly remarkable.` sentiment = `positive` )
    ( text = `Wonderful experience The plot was engaging and entertaining.` sentiment = `positive` )
    ( text = `Superb direction and acting One of the best films I have seen.` sentiment = `positive` )

    " Negative Reviews (8)
    ( text = `Terrible movie Waste of time and money Very disappointed.` sentiment = `negative` )
    ( text = `Awful film Poor acting and boring story Would not recommend.` sentiment = `negative` )
    ( text = `Horrible The worst movie I have ever seen Extremely disappointing.` sentiment = `negative` )
    ( text = `Bad movie with terrible plot Boring and predictable.` sentiment = `negative` )
    ( text = `Disappointing film Poor execution and weak performances.` sentiment = `negative` )
    ( text = `Worst movie ever Horrible acting and stupid storyline.` sentiment = `negative` )
    ( text = `Terrible experience Boring and poorly made Do not waste your time.` sentiment = `negative` )
    ( text = `Awful Poor quality and uninteresting Complete waste of time.` sentiment = `negative` )
  ).

  " 2. Train the model
  DATA(lo_analyzer) = NEW lcl_sentiment_analyzer( ).
  lo_analyzer->train( lt_training_data ).

  " 3. Get user input and convert to string
  DATA(lv_user_text) = CONV string( p_input ).

  " 4. Execute sentiment analysis
  DATA lv_sentiment TYPE string.
  DATA lv_score     TYPE decfloat34.
  DATA lv_conf      TYPE decfloat34.

  lo_analyzer->analyze(
    EXPORTING
      iv_text      = lv_user_text
    IMPORTING
      ev_sentiment = lv_sentiment
      ev_score     = lv_score
      ev_conf      = lv_conf
  ).

  " 5. Print results
  FORMAT COLOR COL_HEADING.
  WRITE: / 'Sentiment Analysis Result'.
  FORMAT COLOR OFF.
  ULINE.

  WRITE: / 'Text:  ', lv_user_text.
  SKIP.

  " Highlight with different colors based on sentiment result
  IF lv_sentiment = 'positive'.
    FORMAT COLOR COL_POSITIVE.
    WRITE: / 'Result: POSITIVE 😊'.
    FORMAT COLOR OFF.
  ELSE.
    FORMAT COLOR COL_NEGATIVE.
    WRITE: / 'Result: NEGATIVE 😞'.
    FORMAT COLOR OFF.
  ENDIF.

  " Format output score and confidence
  WRITE: / 'Confidence:', lv_conf, '%'.
  WRITE: / 'Score:     ', lv_score.

  " Add a bottom prompt message, similar to the Python version experience
  SKIP 2.
  WRITE: / '---------------------------------------------------'.
  WRITE: / 'Click the Back button (F3) to try another sentence!'.
