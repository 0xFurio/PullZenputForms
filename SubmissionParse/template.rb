# email html and/or plain text template

EMAIL_PRE = "<!DOCTYPE HTML>
<head>
    <style type='text/css'>

            table {
                margin-left: auto;
                margin-right: auto;
                min-width: 90%;
            }
            th.b {
                background-color: #A77BCA;
                padding-top: 0.35em;
                padding-bottom: 0.35em;
                text-align: left;
            }
            td.b {
                word-wrap: break-word;
                padding-top: 0.25em;
                padding-bottom: 0.25em;
            }
            th, td {
                padding-left: 1em;
                padding-right: 1em;
            }
            tr:nth-child(even) {
                background-color: #e0e0e0;
            }
            .alert {
                background-color: #cf000d;
                padding-top: 0.1em;
                padding-bottom: 0.1em;
                padding-left: 1em;
                padding-right: 1em;
                color: #000000;
            }

    </style>
    <!--f12 is not a crime-->
</head>"

TD_A  =  "<td>"
TD_AA =  "<td><span class='alert'><strong>"
TD_Z  =  "</td>"
TD_ZZ =  "</strong></span></td>"