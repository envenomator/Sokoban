//#define __USE_MINGW_ANSI_STDIO 1
#include <stdio.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define LOADADDRESS 0x2000
#define LOADADDRESSIZE 2
#define HEADERSIZE 10
#define BUFFERSIZE 128
char linebuffer[BUFFERSIZE];

int getplayerpos(char *string);
int get_goalsfromline(char *string);

int main(int argc, char *argv[])
{
    unsigned zerobyte = 0;
    unsigned int numlevels = 0, level = 0;
    unsigned int outputlength = 0;
    unsigned int playerpos = 0;
    unsigned int * levelheight;
    unsigned int * levelwidth;
    unsigned int * levelgoals;
    unsigned int * levelpayload;
    unsigned int * leveloffset;
    bool playerfound = false;
    FILE *fptr,*outptr;
    
    if(argc <= 2)
    {
        printf("How to use\n");
        exit(1);
    }
    fptr = fopen(argv[1],"r");
    if(fptr == NULL)
    {
        printf("Error opening file\n");   
        exit(1);             
    }
    outptr = fopen(argv[2],"wb");
    if(outptr == NULL)
    {
        printf("Error opening output file\n");
        fclose(fptr);
        exit(1);
    }

    // Determine the number of levels in this file
    while(fgets(linebuffer, sizeof(linebuffer), fptr) != NULL)
    {
        if(strncmp(linebuffer,"Level",5) == 0) numlevels++;
    }
    rewind(fptr);
    printf("%d Levels in file\n",numlevels);

    // OUTPUT LOAD ADDRESS for x16 LOAD function
    fprintf(outptr,"%c%c",(char)LOADADDRESS, LOADADDRESS>>8);
    // OUTPUT #LEVELS as 16-bit integer
    fprintf(outptr,"%c%c",(char)(numlevels), (char)(numlevels>>8));

    
    // determine max width / height per level
    // prepare arrays to store counters per level
    levelheight = malloc(numlevels * sizeof(unsigned int));
    levelwidth = malloc(numlevels * sizeof(unsigned int));
    levelgoals = malloc(numlevels * sizeof(unsigned int));
    levelpayload = malloc(numlevels * sizeof(unsigned int));
    leveloffset = malloc(numlevels * sizeof(unsigned int));

    while(fgets(linebuffer, sizeof(linebuffer), fptr) != NULL)
    {
        if(strncmp(linebuffer,"Level",5) == 0)
        {
            level++; // first level is 0, but marked at '1'
            levelheight[level-1] = 0;
            levelwidth[level-1] = 0;
            levelgoals[level-1] = 0;
            leveloffset[level-1] = 0;
        }
        else
        {
            outputlength = strlen(linebuffer) - 1; //compensate EOL / CR/LF
            // empty line, or payload?
            if(outputlength)
            {
                // store maximum width at this level
                if(levelwidth[level-1] < outputlength) levelwidth[level-1] = outputlength;
                levelheight[level-1]++; // add another line to this level
                levelgoals[level-1] += get_goalsfromline(linebuffer);
            }
        }
    }
    rewind(fptr);

    // now determine the player's position as an address at each level and store it in the array
    level = 0;
    playerfound = false;
    while(fgets(linebuffer, sizeof(linebuffer), fptr) != NULL)
    {
        if(strncmp(linebuffer,"Level",5) == 0)
        {
            level++; // first level is 0, but marked at '1'
            leveloffset[level-1] = 0; // reset offset for the player at this level
            playerfound = false;
        }
        else
        {
            outputlength = strlen(linebuffer) - 1; //compensate EOL / CR/LF
            // empty line, or payload?
            if(outputlength)
            {
                if(playerfound == false)
                {
                    playerpos = getplayerpos(linebuffer);
                    if(playerpos)
                    {
                        leveloffset[level-1] += playerpos;
                        playerfound = true;
                    }
                    else leveloffset[level-1] += levelwidth[level-1];
                }
            }
        }
    }
    rewind(fptr);


    for(int n = 0; n < numlevels; n++)
    {
        // calculate payload for level n
        // as the number of bytes AFTER the initial pointer to the number of levels in the file
        // FILE LAYOUT
        //                ## 2 byte load address
        //  x16 pointer ->## 2 byte number of levels in the file
        //
        //                ## 2 byte start pointer to payload of level 0
        //                ## 2 byte width of level 0 (in characters)
        //                ## 2 byte height of level 0 (in lines)
        //                ## 2 byte number of goals in this level
        //                ## 2 byte ptr to player character in level 0
        //                repeat of these 4 16-bit values for each additional level
        //                ## start payload 0
        // etc
        if(n == 0) levelpayload[n] = LOADADDRESS + LOADADDRESSIZE + (HEADERSIZE * numlevels); 
        else levelpayload[n] = LOADADDRESS + LOADADDRESSIZE + (HEADERSIZE * numlevels) + (n * levelwidth[n-1] * levelheight[n-1]);
        leveloffset[n] = levelpayload[n] + leveloffset[n] - 1; // convert to address
        fprintf(outptr,"%c%c",(char)levelpayload[n],(char)(levelpayload[n]>>8));
        fprintf(outptr,"%c%c",(char)levelwidth[n],(char)(levelwidth[n]>>8));
        fprintf(outptr,"%c%c",(char)levelheight[n],(char)(levelheight[n]>>8));
        fprintf(outptr,"%c%c",(char)levelgoals[n],(char)(levelgoals[n]>>8));
        fprintf(outptr,"%c%c",(char)leveloffset[n],(char)(leveloffset[n]>>8));
    }
    // header generation complete

    // now transform the input to the output file and pad memory space
    level = 0;
    while(fgets(linebuffer, sizeof(linebuffer), fptr) != NULL)
    {
        if(strncmp(linebuffer,"Level",5) == 0)
        {
            level++; // first level is 0, but marked at '1'
        }
        else
        {
            outputlength = strlen(linebuffer) - 1; //compensate EOL / CR/LF
            // empty line, or payload?
            printf("%d\n",outputlength);
            if(outputlength)
            {
                //fprintf(outptr,"%s",linebuffer);
                //fwrite(linebuffer,1,outputlength, outptr);
                // now need to padd to max length with zeroes
                for(int n = 0; n < levelwidth[level-1]; n++)
                {
                    if(n < outputlength) fprintf(outptr,"%c",linebuffer[n]);
                    else fprintf(outptr,"%c",0);
                }
            }
        }
    }

    free(levelheight);
    free(levelwidth);
    free(levelgoals);
    free(levelpayload);
    free(leveloffset);
    fclose(fptr);
    fclose(outptr);
    exit(EXIT_SUCCESS);
}

int getplayerpos(char *string)
{
    unsigned int pos;
    unsigned int length;
    bool found = false;

    length = strlen(string);
    pos = 0;
    while(pos < length)
    {
        if(string[pos] == '@' || string[pos] == '+') break;
        pos++;
    }
    if(pos < length) return pos + 1; // non-zero based position
    else return 0;
}
int get_goalsfromline(char *string)
{
    unsigned int goalnum = 0;
    while(*string)
    {
        if(*string == '.' || *string == '+' || *string == '*') goalnum++;
        string++;
    }
    return goalnum;
}

    /*
    // calculate number of volume records/lines
    t = getc(fptr);
    while(t != EOF)
    {
        if(t == '\n') line++;
        t = getc(fptr);
    }
    printf("Inputfile \"%s\" contains %d records\n",argv[1], line-1);
    items = malloc((line-1) * sizeof(struct item));
    if(items == NULL)
    {
        printf("Error allocating memory, no conversion done\n");
        fclose(fptr);
        fclose(outptr);
        fclose(accoutptr);
        exit(1);
    }
    rewind(fptr);
    line = 1; // return to 1

    // check if quotes are present in inputfile - check only first character!!
    t = getc(fptr);
    if(t == '\"'){
        quotepresent = true;
        tokencorrector = 0;
    }
    else {
        quotepresent = false;
        tokencorrector = 1;
    }
    rewind(fptr);

    // loop through entire file, split in tokens and output selection
    t = getc(fptr);
    while(t != EOF){
        if(t != '\n'){
            // token parse loop
            ungetc(t, fptr); // push character back to the queue
            gettoken(fptr, token);
            kolom++; // token gelezen -> kolom
            if(present(kolommen, kolom))
            {
                if(kolom == CREATIONTIME)
                {
                    // Omzetten die handel
                    if(line > 1)
                    {
                        month = monthnumber(token, quotepresent);
                        fprintf(outptr, "\"%.2s-%02d-%.4s\"\t", token+9-tokencorrector, month,token+21-tokencorrector);
                        snprintf(items[line-2].date,9,"%.4s%02d%.2s",token+21-tokencorrector,month,token+9-tokencorrector);
                    }
                    else fprintf(outptr, "\"Creation Date\"\t");
                }
                else if(kolom == VOLUMESIZE)
                {
                    if(line > 1)
                    {
                        if(!quotepresent)
                        {
                            //correctexponent(token); // make sure to correct e+ to e- notation
                            //sscanf(token,"%lf",&sizef);
                            //size = sizef;
                            size = readfloatorinteger(token);
                        }

                        else {
                            size = readfloatorinteger(token+1);
                        }

                        size /= 1073741824;
                        fprintf(outptr,"\"%lld\"\t",size);
                        items[line-2].size = size;
                    }
                    else fprintf(outptr, "\"Allocated Size (GiB)\"\t");
                }
                else fprintf(outptr, "%s\t",token);
            }
        }
        else
        {
            // restart on new line
            kolom = 0;
            line++; // next line
            putc('\n', outptr);
        }
        
        t = getc(fptr);
    }

    // sort the array on date field
    qsort(items,line-2,sizeof(struct item),comparedates);

    // accumulate and tally the array to 2nd output file
    // items[line-1] == last item
    
    fprintf(accoutptr, "\"Date\"\t\"New allocation (GiB)\"\t\"Total allocation (GiB)\"\t\n");
    i = 0;
    accumulator = 0;
    daytotal = 0;
    while(i < line-2)
    {
        tally = false;
        accumulator += items[i].size;
        daytotal += items[i].size;

        if(i == line-3) // last line reached - don't look beyond last line
        {
            tally = true;
        }
        else
        {
            if(strcmp(items[i].date, items[i+1].date) != 0)
            {
                // next date is different, print out this one
                tally = true;
            }
        }
        if(tally == true)
        {
            fprintf(accoutptr, "\"%.2s-%.2s-%.4s\"\t\"%d\"\t\"%d\"\n",items[i].date+6,items[i].date+4,items[i].date,daytotal,accumulator);                            
            daytotal = 0;            
        }
        i++; // next item in items[]
    }

    fclose(fptr);
    fclose(outptr);
    fclose(accoutptr);
    free(items);
    printf("Conversion complete, outputfile is \"%s\" and \"%s-accumulated\"\n", argv[2],argv[2]);
    return 0;
}

bool present(int *list, int kolomid)
{
    while((*list) != 0)
    {
        if((*list) == kolomid) return true; // found!
        list++;
    }
    return false;
}

void gettoken(FILE *fptr, char *buffer)
{
    char t = getc(fptr);

    while(t != EOF)
    {
        if(t != DELIMITER)
        {
            (*buffer++) = t;
            t = getc(fptr);
        }
        else
        {
            (*buffer) = 0; // terminate token string
            t = EOF; // ensure end of loop
        }
    }
}

void correctexponent(char *token)
{
    while(*token != 0)
    {
        if(*token == '+') *token = '-'; // change E+ notation to E-
        if(*token == 'E') *token = 'e'; // change E to e
        if(*token == ',') *token = '.'; // change to US notation
        token++;
    }
}

__int64 readfloatorinteger(char *token)
{
    __int64 i = 0;
    float base;
    __int16 basemultiplier = 0, temp, exponent; // used for calculating how long the base is
    char *t = token;
    char *part2;
    bool hasexponent = false;

    correctexponent(token);
    while(*t != 0)
    {
        // search to end-of-string for e or E
        if(*t == 'e' || *t == 'E')
        {
            // this is an exponent number, split in two parts
            // first calculate the base length up to e/E
            basemultiplier = t - token - 2; // -1 to correct the ',' sign, -1 to correct for digit before ,/.
            part2 = t + 2;
            hasexponent = true;
        }
        t++;
    }
    if(hasexponent == true)
    {
        // scan in two parts
        // first scan the exponent, so we can change it later
        //sscanf(token, "%f", &base); // scan first double (without exponent)

        // first scan the exponent
        sscanf(part2, "%d", &exponent); // scan to temporary number

        // now change the original exponent to E+00, so the scanf function for base works
        *part2 = '0';
        part2++;
        *part2 = '0'; // resulting in baseE+00
        sscanf(token, "%f", &base);

        // do base*10^basemultiplier
        temp = basemultiplier;
        while(temp > 0)
        {
            // multiply the base number by 10^multiplier
            // so if the number is 1,03 - we multiply by 100 to get at 103
            base = base * 10;
            temp--;
        }
        i = base; // first part of the result
        // now multiply the base by 10 for each component left
        temp = exponent - basemultiplier;
        while(temp > 0)
        {
            i = i * 10;
            temp--;
        }
    }
    else sscanf(token, "%lld", &i); // scan as an integer
    return i;
}
int monthnumber(char *token, bool quotepresent)
{
    int selection = 0;
    if(quotepresent){
        token += 5;
    }
    else token += 4;

    for(int i = 0; i < 3; i++) selection += *(token+i);

    switch (selection)
    {
        case 'J'+'a'+'n':
            return 1;
        case 'F'+'e'+'b':
            return 2;
        case 'M'+'a'+'r':
            return 3;
        case 'A'+'p'+'r':
            return 4;
        case 'M'+'a'+'y':
            return 5;
        case 'J'+'u'+'n':
            return 6;
        case 'J'+'u'+'l':
            return 7;
        case 'A'+'u'+'g':
            return 8;
        case 'S'+'e'+'p':
            return 9;
        case 'O'+'c'+'t':
            return 10;
        case 'N'+'o'+'v':
            return 11;
        case 'D'+'e'+'c':
            return 12;
        default:
            return 0;
    }
}

int comparedates(const void *p, const void *q)
{
    const struct item *p1 = p;
    const struct item *q1 = q;
    int result = strcmp(p1->date, q1->date);

    return result;
}
*/
