#include <SPI.h>
#include <RF24.h>
RF24 radio(46,47);
const byte addr[6]="H2M01";
void setup(){Serial.begin(115200);
 radio.begin();radio.setChannel(76);radio.setDataRate(RF24_250KBPS);
 radio.openReadingPipe(2,addr);radio.startListening();}
void loop(){uint8_t pipe;uint32_t n;
 if(radio.available(&pipe)){
   radio.read(&n,sizeof(n));
   Serial.print("pipe=");Serial.print(pipe);
   Serial.print(" value=");Serial.println(n);
 }}
