    #include <stdio.h>
    extern char **environ;
    int main(int argc, char **argv) {
        printf("%p\n", environ);
        return 0;
    }

