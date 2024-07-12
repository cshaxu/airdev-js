type Config = {
    [key: string]: string | Config;
};
export declare function decryptConfig<T extends Config>(config: T, password: string): T;
export {};
