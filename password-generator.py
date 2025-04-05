
import random
import string
import secrets

symbol1 = "!\#¤%&/()=?*^<>|¡@£$€¥{[]±·¸-,:;_`"
symbol2 = "@€|;[!]<>#·&¿¸/:^()¡¤%-{£*¥=,_±$`}"
symbol3 = "¡@£$€¥{[]±!&/()=?*^<\|·¸-,:;_`¤%>="
symbol4 = "¡¸{[]±·_`!\#¤%@£-,:$€¥&/()=?*^<;>|"

while True:
    print( )
    antal = int (input ("How many passwords do you want?: "))

    for i in range (0,antal):

        password1 = "".join(random.choices((string.ascii_letters), k=2))

        password2 = "".join(random.choices((string.ascii_letters), k=2))
	
        password3 = "".join(random.choices((string.ascii_letters), k=2))

        password4 = "".join(random.choices((string.ascii_letters), k=2))

        random_symbols1 = "".join(secrets.choice(symbol1) for _ in range(2))

        random_symbols2 = "".join(secrets.choice(symbol2) for _ in range(2))

        random_symbols3 = "".join(secrets.choice(symbol3) for _ in range(2))

        random_symbols4 = "".join(secrets.choice(symbol4) for _ in range(2))

        nr1 = random.randint (10,99)

        nr2 = random.randint (10,99)

        nr3 = random.randint (10,99)

        nr4 = random.randint (10,99)

        result = password1 + random_symbols1 + str(nr1) + password2 + random_symbols2 + str(nr2) + password3 + random_symbols3 + str(nr3) + password4 + random_symbols4 + str(nr4)
        
        print(result)
